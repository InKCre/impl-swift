import Foundation
import PeerCore
import PostgresNIO
import Testing

private actor QueryBoundary {
    private var arrived = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    func pause() async {
        arrived = true
        arrival?.resume()
        arrival = nil
        await withCheckedContinuation { release = $0 }
    }
    func waitUntilPaused() async {
        if !arrived { await withCheckedContinuation { arrival = $0 } }
    }
    func resume() {
        release?.resume()
        release = nil
    }
}

@Suite(.enabled(if: ProcessInfo.processInfo.environment["INKCRE_CAPTURE_TEST_DATABASE"] != nil))
struct PeerCancellationTests {
    enum Interruption: Sendable, CaseIterable { case cancel, shutdown }

    @Test(arguments: Interruption.allCases)
    func interruptionBetweenQueriesSettlesAndRollsBack(_ interruption: Interruption) async throws {
        let (target, password) = try configuration()
        let database = PeerDatabase()
        let boundary = QueryBoundary()
        let marker = "between-queries-\(UUID())"
        let operation = Task {
            try await database.withConnection(for: target, password: password) { connection in
                try await connection.withTransaction { connection in
                    try await connection.query(
                        "INSERT INTO inkcre.blocks(resolver,content) VALUES ('core.text.v1',\(marker))"
                    )
                    await boundary.pause()
                    // Cancellation attempts another body query; shutdown attempts COMMIT itself.
                    if interruption == .cancel { try await connection.query("SELECT 1") }
                }
            }
        }
        await boundary.waitUntilPaused()
        let start = ContinuousClock.now
        switch interruption {
        case .cancel: operation.cancel()
        case .shutdown: await database.shutdown()
        }
        await boundary.resume()
        do {
            try await operation.value
            Issue.record("Interrupted transaction unexpectedly completed")
        } catch {
            if interruption == .cancel {
                #expect(error is CancellationError)
            } else {
                if case .connection = PeerDatabase.failure(error) {
                } else {
                    Issue.record("A closed connection must remain retryable")
                }
                if case .outcomeUnknown = PeerDatabase.failure(error, dispatched: true) {
                } else {
                    Issue.record("A dispatched write must retain result verification")
                }
            }
        }
        #expect(start.duration(to: .now) < .seconds(2))
        let count = try await database.withConnection(for: target, password: password) {
            connection in
            try await connection.query(
                "SELECT count(*)::integer FROM inkcre.blocks WHERE content=\(marker)"
            ).first?.decode(Int.self)
        }
        #expect(count == 0)
        await database.shutdown()
    }

    @Test func ordinaryDatabaseFailureRollsBackAndKeepsItsError() async throws {
        let (target, password) = try configuration()
        let database = PeerDatabase()
        let marker = "rollback-error-\(UUID())"
        try await database.withConnection(for: target, password: password) { connection in
            do {
                try await connection.withTransaction { connection in
                    try await connection.query(
                        "INSERT INTO inkcre.blocks(resolver,content) VALUES ('core.text.v1',\(marker))"
                    )
                    try await connection.query("SELECT 1/0")
                }
                Issue.record("Expected PostgreSQL division-by-zero error")
            } catch let error as PSQLError {
                #expect(error.serverInfo?[.sqlState] == "22012")
            }
            // Same borrowed connection remains usable and the earlier write did not survive.
            let rows = try await connection.query(
                "SELECT count(*)::integer FROM inkcre.blocks WHERE content=\(marker)")
            #expect(try rows.first?.decode(Int.self) == 0)
        }
        await database.shutdown()
    }

    private func configuration() throws -> (ConnectionTarget, String) {
        let env = ProcessInfo.processInfo.environment
        return (
            ConnectionTarget(
                host: "127.0.0.1", port: Int(env["INKCRE_CAPTURE_TEST_PORT"] ?? "5432")!,
                database: try #require(env["INKCRE_CAPTURE_TEST_DATABASE"]),
                username: "inkcre_core", tls: .disable),
            try #require(env["INKCRE_CAPTURE_TEST_PASSWORD"])
        )
    }
}
