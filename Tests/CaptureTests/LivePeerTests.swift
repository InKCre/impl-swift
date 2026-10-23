import Capture
import Foundation
import PeerCore
import Security
import Testing

@Test(.enabled(if: ProcessInfo.processInfo.environment["INKCRE_CAPTURE_TEST_DATABASE"] != nil))
func nativeTransactionCommitsOriginalImageOnceAndRecoversAfterRestart() async throws {
  let env = ProcessInfo.processInfo.environment
  let target = ConnectionTarget(
    host: "127.0.0.1", port: Int(env["INKCRE_CAPTURE_TEST_PORT"] ?? "5432")!,
    database: try #require(env["INKCRE_CAPTURE_TEST_DATABASE"]), username: "inkcre_core",
    tls: .disable)
  let password = try #require(env["INKCRE_CAPTURE_TEST_PASSWORD"])
  let database = PeerDatabase()
  let client = CaptureClient(database: database)
  let pg = try await database.client(for: target, password: password)
  struct Fixture: Decodable { let payload: CapturePayload }
  let fixtureURL = try #require(
    Bundle.module.url(forResource: "capture-v1", withExtension: "json", subdirectory: "Fixtures"))
  let fixture = try CaptureJSON.decode([Fixture].self, from: Data(contentsOf: fixtureURL))[1]
  let payload = CapturePayload(
    entry: .paste, origin: fixture.payload.origin, materials: fixture.payload.materials,
    annotation: fixture.payload.annotation)
  var record = CaptureRecord(payload: payload)
  record.target = target
  let submission = record
  async let a = client.submit(submission, secret: password)
  async let b = client.submit(submission, secret: password)
  async let c = client.submit(submission, secret: password)
  let results = try await [a, b, c]
  let result = try #require(results.first)
  #expect(results.allSatisfy { $0 == result })
  let rows = try await pg.query(
    """
    WITH RECURSIVE captured(id) AS (SELECT \(result.rootBlockID)::integer UNION
      SELECT to_ FROM inkcre.relations JOIN captured ON from_=captured.id)
    SELECT b.resolver,b.content,s.data FROM inkcre.blocks b JOIN captured USING(id)
      LEFT JOIN inkcre.storage_blobs s ON s.id=CASE WHEN b.storage=-4 THEN (b.content::jsonb->>'blob_id')::uuid END
    """)
  var blockCount = 0
  for try await (resolver, content, bytes) in rows.decode((String, String, Data?).self) {
    blockCount += 1
    if resolver == "core.image.v1" { #expect(bytes == payload.materials[1].data) }
    if resolver == "core.text.v1" {
      #expect([payload.materials[0].text, payload.annotation].contains(content))
    }
  }
  #expect(blockCount == 5)

  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let service = "dev.inkcre.native.acceptance.\(UUID().uuidString)"
  let credentials = CredentialStore(service: service)
  try credentials.save(password, for: target.id)
  defer {
    SecItemDelete(
      [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        as CFDictionary)
    try? FileManager.default.removeItem(at: directory)
  }
  // Commit has happened but the local process has not observed its response.
  let store = try CaptureStore(url: directory.appendingPathComponent("capture.sqlite"))
  _ = try await store.freeze(CaptureRecord(payload: payload), target: target)
  _ = try await store.markDispatch(payload.submissionID)
  let reopened = try CaptureStore(url: directory.appendingPathComponent("capture.sqlite"))
  try await CaptureQueue(store: reopened, credentials: credentials, client: client).process(
    force: true)
  let recovered = try #require(try await reopened.record(payload.submissionID))
  #expect(recovered.state == .confirmed && recovered.payload == nil)
  #expect(recovered.result == result)

  var changed = payload
  changed.annotation = "另一份材料"
  var conflict = CaptureRecord(payload: changed)
  conflict.target = target
  await #expect(throws: PeerError.self) { _ = try await client.submit(conflict, secret: password) }

  let before = try await pg.query("SELECT count(*) FROM inkcre.blocks").decode(Int.self).first {
    _ in true
  }
  await #expect(throws: (any Error).self) {
    try await pg.withTransaction(logger: PeerDatabase.logger) { connection in
      _ = try await InfoBase.persist(
        blocks: [GraphBlock(id: -1, resolver: "core.text.v1", content: "must rollback")],
        relations: [GraphRelation(from_: -1, to_: -999, content: "invalid")], blobs: [:],
        on: connection)
    }
  }
  let after = try await pg.query("SELECT count(*) FROM inkcre.blocks").decode(Int.self).first { _ in
    true
  }
  #expect(before == after)
  try await pg.query("DELETE FROM inkcre.blocks WHERE id=\(result.rootBlockID)")
  #expect(try await client.submit(record, secret: password).availability == .deleted)
  try await database.setEnabled(
    false, target: target, password: password, extension: CaptureClient.descriptor)
  do {
    _ = try await client.submit(record, secret: password)
    Issue.record("停用后不得继续共享写入")
  } catch PeerError.needsAction(let message) { #expect(message.contains("停用")) }
  await #expect(throws: PeerError.self) {
    _ = try await client.submit(record, secret: password)
  }
  try await pg.query(
    "DELETE FROM inkcre.extension_peer_participations WHERE peer_id=\(target.peerID)")
  await #expect(throws: PeerError.self) {
    _ = try await client.submit(record, secret: password)
  }
  let removed = try await pg.query(
    "SELECT count(*) FROM inkcre.extension_peer_participations WHERE peer_id=\(target.peerID)"
  ).decode(Int.self).first { _ in true }
  #expect(removed == 0)
  // An explicit enable is allowed to create a first participation before Capture starts.
  try await database.setEnabled(
    true, target: target, password: password, extension: CaptureClient.descriptor)
  _ = try await client.submit(record, secret: password)
  let first = ConnectionTarget(
    host: target.host, port: target.port, database: target.database, username: target.username,
    tls: target.tls)
  try await database.setEnabled(
    true, target: first, password: password, extension: CaptureClient.descriptor)
  var firstRecord = CaptureRecord(payload: CapturePayload(materials: [Material(text: "首次准入")]))
  firstRecord.target = first
  try await pg.query(
    "DELETE FROM inkcre.extension_peer_participations WHERE peer_id=\(first.peerID)")
  await #expect(throws: PeerError.self) {
    _ = try await client.submit(firstRecord, secret: password)
  }
  let removedBeforeFirstJoin = try await pg.query(
    "SELECT count(*) FROM inkcre.extension_peer_participations WHERE peer_id=\(first.peerID)"
  ).decode(Int.self).first { _ in true }
  #expect(removedBeforeFirstJoin == 0)
  try await database.setEnabled(
    true, target: first, password: password, extension: CaptureClient.descriptor)
  _ = try await client.submit(firstRecord, secret: password)
  await database.shutdown()
}
