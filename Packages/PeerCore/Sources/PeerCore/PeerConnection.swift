import Logging
import PostgresNIO

/// A connection borrowed inside PeerDatabase.withConnection. Do not retain it beyond that scope.
public struct PeerConnection: Sendable {
    let connection: PostgresConnection

    /// Collect a query before returning. Current callers materialize their results; this is not a
    /// streaming API. Check and write share the event loop so close cannot strand a driver promise.
    @discardableResult
    public func query(_ query: PostgresQuery, logger: Logger = PeerDatabase.logger) async throws
        -> [PostgresRow]
    {
        try Task.checkCancellation()
        let result: PostgresQueryResult = try await connection.eventLoop.flatSubmit {
            guard !connection.isClosed else {
                return connection.eventLoop.makeFailedFuture(
                    ClosedConnection())
            }
            return connection.query(query, logger: logger)
        }.get()
        try Task.checkCancellation()
        return result.rows
    }

    func close() async {
        connection.close().whenFailure { _ in }
        // close() may return an already-succeeded future as soon as isActive becomes false.
        // closeFuture waits for handler cleanup; the pool observes the same future.
        try? await connection.closeFuture.get()
    }

    private struct ClosedConnection: Error {}

    public func withTransaction<Result: Sendable>(
        logger: Logger = PeerDatabase.logger,
        _ operation: @Sendable (PeerConnection) async throws -> Result
    ) async throws -> Result {
        try await query("BEGIN", logger: logger)
        let result: Result
        do {
            result = try await operation(self)
        } catch {
            // Cancellation closes the socket in the enclosing lease and PostgreSQL rolls back.
            // Never issue another command on that connection after cancellation.
            if Task.isCancelled { throw error }
            do {
                try await query("ROLLBACK", logger: logger)
            } catch let rollbackError {
                await close()
                throw PeerTransactionError(operationError: error, rollbackError: rollbackError)
            }
            throw error
        }
        do {
            try await query("COMMIT", logger: logger)
        } catch {
            // A failed/uncertain commit must not return an open transaction to the pool.
            await close()
            throw error
        }
        return result
    }
}

public struct PeerTransactionError: Error {
    public let operationError: any Error
    public let rollbackError: any Error
}
