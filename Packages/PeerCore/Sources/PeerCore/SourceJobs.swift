import Foundation
import PostgresNIO

public struct SourceJob: Sendable {
    public let id: Int
    public let deadline: Date
}

public enum SourceJobs {
    public static let type = "core.source.collect.v1"

    public static func submit(source: Int, on connection: PostgresConnection) async throws -> Int {
        let parameters = "{\"source\":\(source),\"config\":{}}"
        let rows = try await connection.query(
            """
            INSERT INTO inkcre.jobs(type,parameters,timeout_seconds,status)
            SELECT id,\(parameters)::jsonb,default_timeout_seconds,'pending' FROM inkcre.job_types WHERE id=\(type)
            RETURNING id
            """, logger: PeerDatabase.logger)
        for try await id in rows.decode(Int.self) { return id }
        throw PeerError.needsAction("信息库尚未登记来源扫描命令。")
    }

    public static func pending(source: Int, on client: PostgresClient) async throws -> [Int] {
        try await client.query(
            "UPDATE inkcre.jobs SET status='timed_out' WHERE type=\(type) AND status='running' AND parameters->'source'=to_jsonb(\(source)::bigint) AND started_at + timeout_seconds * interval '1 second' < now()"
        )
        try await client.query(
            "UPDATE inkcre.jobs SET status='aborted' WHERE type=\(type) AND status='pending' AND abort_requested AND parameters->'source'=to_jsonb(\(source)::bigint)"
        )
        let rows = try await client.query(
            "SELECT id FROM inkcre.jobs WHERE type=\(type) AND status='pending' AND parameters->'source'=to_jsonb(\(source)::bigint) ORDER BY id"
        )
        var ids: [Int] = []
        for try await id in rows.decode(Int.self) { ids.append(id) }
        return ids
    }

    /// Eligibility is checked under the Source lock by the capability before claiming.
    public static func claim(_ id: Int, source: Int, on connection: PostgresConnection) async throws
        -> SourceJob?
    {
        let rows = try await connection.query(
            """
            UPDATE inkcre.jobs SET status='running' WHERE id=\(id) AND type=\(type) AND status='pending'
              AND NOT abort_requested AND (parameters || '{"config":{}}'::jsonb)=\("{\"source\":\(source),\"config\":{}}")::jsonb
              AND COALESCE(parameters->'config','{}'::jsonb)='{}'::jsonb
            RETURNING id,started_at + timeout_seconds * interval '1 second'
            """, logger: PeerDatabase.logger)
        for try await (id, deadline) in rows.decode((Int, Date).self) {
            return SourceJob(id: id, deadline: deadline)
        }
        return nil
    }

    public static func check(_ job: SourceJob, on client: PostgresClient) async throws {
        try Task.checkCancellation()
        if Date() >= job.deadline { throw PeerError.needsAction("扫描已超时。") }
        let rows = try await client.query(
            "SELECT status::text,abort_requested FROM inkcre.jobs WHERE id=\(job.id)")
        for try await (status, aborted) in rows.decode((String, Bool).self) {
            guard status == "running", !aborted else { throw CancellationError() }
            return
        }
        throw CancellationError()
    }

    public static func close(
        _ job: SourceJob, status: String, state: String, on client: PostgresClient
    ) async throws {
        guard ["finished", "failed", "timed_out", "aborted"].contains(status) else {
            throw PeerError.invalid("无效的任务终态。")
        }
        try await client.query(
            "UPDATE inkcre.jobs SET status=\(status)::inkcre.jobstatus,state=\(state)::jsonb WHERE id=\(job.id) AND status='running'"
        )
    }
}
