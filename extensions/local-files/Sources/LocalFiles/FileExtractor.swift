import AppKit
import CryptoKit
import Foundation
import PDFKit
import PeerCore
import SwiftSoup
import UniformTypeIdentifiers

public enum FileExtractor {
  public static let maximumInputBytes = 64 * 1_024 * 1_024
  public static let maximumTextBytes = 8 * 1_024 * 1_024

  public static func format(for url: URL) -> String? {
    switch url.pathExtension.lowercased() {
    case "pdf": "pdf"
    case "docx": "docx"
    case "md", "markdown": "markdown"
    case "org": "org"
    case "html", "htm": "html"
    case "txt", "text", "": "text"
    default:
      UTType(filenameExtension: url.pathExtension)?.conforms(to: .text) == true ? "text" : nil
    }
  }

  public static func files(in directory: URL) throws -> [URL] {
    guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
      throw PeerError.needsAction("目录当前不可访问。")
    }
    let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
    var enumerationError: (any Error)?
    guard
      let enumerator = FileManager.default.enumerator(
        at: directory, includingPropertiesForKeys: Array(keys),
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { _, error in
          enumerationError = error
          return false
        })
    else { throw PeerError.needsAction("无法读取目录。") }
    var files: [URL] = []
    for case let url as URL in enumerator {
      try Task.checkCancellation()
      let values = try url.resourceValues(forKeys: keys)
      if values.isSymbolicLink == true {
        enumerator.skipDescendants()
        continue
      }
      if values.isRegularFile == true, format(for: url) != nil { files.append(url) }
    }
    if let enumerationError { throw enumerationError }
    return files.sorted { $0.path < $1.path }
  }

  public static func observe(_ url: URL, peer: UUID, previous: FileRevision? = nil) throws
    -> FileObservation
  {
    try Task.checkCancellation()
    guard let format = format(for: url) else { throw PeerError.invalid("不支持的文件格式。") }
    var metadata = FileMetadata(
      location: try PeerFileLocation(peer: peer, path: url.path).uri,
      format: format, identity: nil, available: true, observed_at: Date(), revision: nil, issue: nil
    )
    do {
      let before = try url.resourceValues(forKeys: [
        .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
        .volumeUUIDStringKey, .creationDateKey,
      ])
      guard before.isSymbolicLink != true, before.isRegularFile == true else {
        throw PeerError.invalid("不是普通文件。")
      }
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      if let volume = before.volumeUUIDString,
        let number = attributes[.systemFileNumber] as? NSNumber, let created = before.creationDate
      {
        metadata.identity = FileIdentity(
          volume: volume, number: number.uint64Value, created: created)
      }
      guard let size = before.fileSize, size <= maximumInputBytes else {
        throw PeerError.invalid("文件超过 64 MiB。")
      }
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      let data = try handle.read(upToCount: maximumInputBytes + 1) ?? Data()
      guard data.count <= maximumInputBytes else { throw PeerError.invalid("文件超过 64 MiB。") }
      let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      let unchanged =
        previous?.sha256 == digest && previous?.extractor == LocalFilesContract.extractor
      let text = unchanged ? nil : try extract(data, format: format)
      if let text, text.utf8.count > maximumTextBytes { throw PeerError.invalid("提取文字超过 8 MiB。") }
      let after = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [
        .fileSizeKey, .contentModificationDateKey,
      ])
      let afterAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
      guard before.fileSize == after.fileSize,
        before.contentModificationDate == after.contentModificationDate,
        attributes[.systemFileNumber] as? NSNumber == afterAttributes[.systemFileNumber]
          as? NSNumber
      else { throw PeerError.needsAction("文件仍在变化，等待重新读取。") }
      try Task.checkCancellation()
      metadata.revision =
        unchanged
        ? previous
        : FileRevision(
          sha256: digest,
          extractor: LocalFilesContract.extractor, extracted_at: Date(),
          scope: format == "docx" ? "main_document" : format == "pdf" ? "text_layer" : "text")
      return FileObservation(metadata: metadata, text: text)
    } catch is CancellationError { throw CancellationError() } catch {
      metadata.issue = error.localizedDescription
      return FileObservation(metadata: metadata, text: nil)
    }
  }

  public static func extract(_ data: Data, format: String) throws -> String {
    switch format {
    case "pdf":
      guard let document = PDFDocument(data: data) else { throw PeerError.invalid("PDF 已损坏。") }
      guard !document.isLocked else { throw PeerError.needsAction("PDF 需要密码。") }
      let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(
        separator: "\n\n")
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw PeerError.needsAction("PDF 没有可提取的文字层。")
      }
      return text
    case "docx":
      let text = try NSAttributedString(
        data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
        documentAttributes: nil
      ).string
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw PeerError.needsAction("DOCX 没有可提取的主文档文字。")
      }
      return text
    default:
      let text = try decode(data)
      if format != "html" { return text }
      let document = try SwiftSoup.parse(text)
      try document.select("script,style,template").remove()
      guard let body = document.body() else { throw PeerError.invalid("HTML 缺少正文。") }
      for br in try body.select("br") { try br.replaceWith(TextNode("\n", "")) }
      for block in try body.select("p,div,h1,h2,h3,h4,h5,h6,li,pre,blockquote,tr") {
        try block.prependText("\n").appendText("\n")
      }
      return try body.text(trimAndNormaliseWhitespace: false).trimmingCharacters(
        in: .whitespacesAndNewlines)
    }
  }

  private static func decode(_ data: Data) throws -> String {
    if data.starts(with: [0xff, 0xfe]), let text = String(data: data, encoding: .utf16) {
      return text
    }
    if data.starts(with: [0xfe, 0xff]), let text = String(data: data, encoding: .utf16) {
      return text
    }
    guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else {
      throw PeerError.invalid("文字编码无法识别；支持 UTF-8 或带 BOM 的 UTF-16。")
    }
    return text.hasPrefix("\u{feff}") ? String(text.dropFirst()) : text
  }
}
