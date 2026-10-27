import AppKit
import LocalFiles
import SwiftSoup
import SwiftUI
import WebKit
import cmark_gfm
import cmark_gfm_extensions

struct FileContentView: View {
    let content: String
    let resolver: String
    var body: some View {
        if resolver == "core.text.v1" {
            Text(content.isEmpty ? "空白文本" : content).textSelection(.enabled).frame(
                maxWidth: .infinity, alignment: .leading)
        } else {
            switch Result(catching: { try readingDocument(content, resolver: resolver) }) {
            case .success(let html): FileWebView(html: html).frame(minHeight: 400)
            case .failure(let error):
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
            }
        }
    }
}

func readingDocument(_ content: String, resolver: String) throws -> String {
    let html = resolver == "core.markdown.v1" ? try markdownHTML(content) : content
    let document = try SwiftSoup.parse(html)
    for resource in try document.select("[src],[poster]") {
        for attribute in ["src", "poster"] where resource.hasAttr(attribute) {
            let address = try resource.attr(attribute)
            let label = try resource.attr(resource.hasAttr("alt") ? "alt" : "label")
            let link = Element(Tag("a"), "")
            try link.attr("href", address).text(label.isEmpty ? address : label)
            let media =
                resource.parents().array().first { ["video", "audio"].contains($0.tagName()) }
                ?? resource
            try media.after(link)
            try resource.removeAttr(attribute)
        }
    }
    for media in try document.select("video,audio") { try media.unwrap() }
    try document.select("img,source,track").remove()
    let allowed = try Whitelist.relaxed().addTags(
        "article", "section", "header", "footer", "time", "del", "s", "input"
    )
    .addAttributes("time", "datetime").addAttributes("input", "type", "checked", "disabled")
    .addAttributes(":all", "id").preserveRelativeLinks(true)
    .addProtocols("a", "href", "#")
    .addEnforcedAttribute("input", "disabled", "disabled")
    guard let cleaned = try SwiftSoup.clean(try document.outerHtml(), allowed) else {
        throw CocoaError(.coderInvalidValue)
    }
    let safe = try SwiftSoup.parse(cleaned)
    for input in try safe.select("input") {
        if try input.attr("type").lowercased() != "checkbox" { try input.remove() }
    }
    for link in try safe.select("a[href]") {
        let address = try link.attr("href")
        if address.hasPrefix("#") { continue }
        if let url = URL(string: address),
            ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        {
            try link.attr("rel", "noopener noreferrer")
        } else {
            try link.removeAttr("href")
        }
    }
    let body = try safe.body()?.html() ?? ""
    return """
        <!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'nonce-inkcre-reader'"><meta name="referrer" content="no-referrer"><style nonce="inkcre-reader">:root{color-scheme:light dark}body{margin:0;font:16px/1.65 system-ui;overflow-wrap:anywhere}h1,h2,h3,h4,h5,h6{line-height:1.35;font-weight:600}h1{font-size:1.5em}h2{font-size:1.25em}h3,h4,h5,h6{font-size:1.1em}pre{white-space:pre;overflow-x:auto;tab-size:4}code{font-family:ui-monospace,monospace}table{border-collapse:collapse}th,td{padding:.35em .7em;border:1px solid GrayText;text-align:start}blockquote{margin-inline:0;padding-inline-start:1em;border-inline-start:2px solid GrayText}a{color:inherit}input{pointer-events:none}</style></head><body>\(body)</body></html>
        """
}

private func markdownHTML(_ source: String) throws -> String {
    cmark_gfm_core_extensions_ensure_registered()
    let options = CMARK_OPT_UNSAFE
    guard let parser = cmark_parser_new(options) else { throw CocoaError(.coderInvalidValue) }
    defer { cmark_parser_free(parser) }
    for name in ["table", "strikethrough", "autolink", "tasklist"] {
        guard let syntax = cmark_find_syntax_extension(name),
            cmark_parser_attach_syntax_extension(parser, syntax) != 0
        else { throw CocoaError(.coderInvalidValue) }
    }
    source.withCString { cmark_parser_feed(parser, $0, source.utf8.count) }
    guard let node = cmark_parser_finish(parser) else { throw CocoaError(.coderInvalidValue) }
    defer { cmark_node_free(node) }
    guard let html = cmark_render_html(node, options, cmark_parser_get_syntax_extensions(parser))
    else { throw CocoaError(.coderInvalidValue) }
    defer { free(html) }
    return String(cString: html)
}

private struct FileWebView: NSViewRepresentable {
    let html: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.underPageBackgroundColor = .clear
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.html != html else { return }
        context.coordinator.html = html
        view.loadHTMLString(html, baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var html: String?
        func webView(
            _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = action.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.scheme == "about" {
                decisionHandler(.allow)
                return
            }
            if action.navigationType == .linkActivated,
                ["http", "https"].contains(url.scheme ?? "")
            {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }
}
