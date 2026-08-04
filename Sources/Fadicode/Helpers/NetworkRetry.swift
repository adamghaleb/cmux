import Foundation

/// Errors related to HTTP response status codes, used by the retry logic
/// to distinguish retryable server errors from non-retryable client errors.
enum HTTPRetryError: Error {
    /// Server returned a 5xx status code (retryable).
    case serverError(statusCode: Int, data: Data)
    /// Server returned a 4xx status code (not retryable).
    case clientError(statusCode: Int, data: Data)
}

/// Executes an async operation with retry logic and exponential backoff.
///
/// Retries on 5xx HTTP errors and network-level (`URLError`) failures.
/// Does **not** retry on 4xx client errors or cancellation.
///
/// - Parameters:
///   - maxAttempts: Maximum number of attempts (default 3).
///   - baseDelay: Initial delay in seconds before the first retry (default 1.0).
///   - operation: The async throwing closure to execute.
/// - Returns: The result of the operation on success.
/// - Throws: The last error encountered after all attempts are exhausted,
///           or immediately on non-retryable errors.
func withRetry<T>(
    maxAttempts: Int = 3,
    baseDelay: TimeInterval = 1.0,
    operation: () async throws -> T
) async throws -> T {
    var lastError: Error?
    for attempt in 0..<maxAttempts {
        do {
            return try await operation()
        } catch {
            // Never retry on cancellation.
            if error is CancellationError { throw error }
            if let urlError = error as? URLError, urlError.code == .cancelled { throw error }

            // Never retry on 4xx client errors.
            if let httpError = error as? HTTPRetryError {
                switch httpError {
                case .clientError:
                    throw error
                case .serverError:
                    break // retryable
                }
            }

            lastError = error

            if attempt < maxAttempts - 1 {
                let delay = baseDelay * pow(2.0, Double(attempt))
                let jitter = Double.random(in: 0...0.5)
                try await Task.sleep(nanoseconds: UInt64((delay + jitter) * 1_000_000_000))
            }
        }
    }
    throw lastError!
}

/// Performs a URLSession data request with automatic retry on 5xx and network errors.
///
/// Returns the raw `(Data, HTTPURLResponse)` tuple. Throws `HTTPRetryError.clientError`
/// immediately on 4xx, and retries on 5xx/network failures up to `maxAttempts` times.
func fetchWithRetry(
    request: URLRequest,
    session: URLSession = .shared,
    maxAttempts: Int = 3,
    baseDelay: TimeInterval = 1.0
) async throws -> (Data, HTTPURLResponse) {
    try await withRetry(maxAttempts: maxAttempts, baseDelay: baseDelay) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if (500...599).contains(httpResponse.statusCode) {
            throw HTTPRetryError.serverError(statusCode: httpResponse.statusCode, data: data)
        }
        if (400...499).contains(httpResponse.statusCode) {
            throw HTTPRetryError.clientError(statusCode: httpResponse.statusCode, data: data)
        }
        return (data, httpResponse)
    }
}
