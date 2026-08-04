import Foundation

/// Summary of what Claude did and what it needs from the user, shown after idle transition.
struct CompletionSummary: Equatable {
    let whatHappened: String
    let whatNeeded: String
    let suggestedPrompt: String?
}

/// A timestamped wrapper around a CompletionSummary for the rolling history log.
struct CompletionHistoryEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let summary: CompletionSummary

    var relativeTime: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return String(localized: "activity.relativeTime.justNow", defaultValue: "just now") }
        if interval < 3600 { return String(localized: "activity.relativeTime.minutesAgo \(Int(interval / 60))", defaultValue: "\(Int(interval / 60))m ago") }
        return String(localized: "activity.relativeTime.hoursAgo \(Int(interval / 3600))", defaultValue: "\(Int(interval / 3600))h ago")
    }
}

/// Lightweight Anthropic API client that generates short summaries of terminal activity.
/// Rate limited to max 1 call per 5s. Uses Claude Haiku for fast, cheap summaries.
/// Heuristic fallback is always available instantly via `heuristicSummary()`.
///
/// **Privacy**: API calls are gated behind the `FadicodeLLMSummariesEnabled` user default.
/// Terminal content is only sent when the user has explicitly opted in via Settings.
@MainActor
class ClaudeActivitySummary {
    static let shared = ClaudeActivitySummary()

    private var apiKey: String {
        UserDefaults.standard.string(forKey: "FadicodeAnthropicAPIKey") ?? ""
    }
    private let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model = "claude-haiku-4-5-20251001"

    /// Whether LLM-powered summaries are enabled (user opt-in).
    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "FadicodeLLMSummariesEnabled") && !apiKey.isEmpty
    }

    /// Minimum interval between API calls (seconds).
    private let minInterval: TimeInterval = 5.0
    private var lastCallTime: Date = .distantPast
    private var inFlight = false

    /// Shared streaming session — reused across calls to avoid per-request allocation.
    private var streamingSession: URLSession?

    private init() {}

    /// Request a 3-5 word summary of what the terminal is doing.
    /// Returns nil on error, rate limit, or if LLM summaries are disabled.
    func summarize(terminalContent: String, completion: @escaping (String?) -> Void) {
        guard isEnabled else {
            completion(nil)
            return
        }

        // Rate limit
        let now = Date()
        guard now.timeIntervalSince(lastCallTime) >= minInterval else {
            completion(nil)
            return
        }
        guard !inFlight else {
            completion(nil)
            return
        }

        inFlight = true
        lastCallTime = now

        // Send only the last 1500 chars for speed
        let trimmed = String(terminalContent.suffix(1500))

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 12,
            "messages": [
                [
                    "role": "user",
                    "content": "What is this terminal doing right now? Reply with ONLY 3-5 words, present tense, no punctuation. Examples: Reading config files, Writing unit tests, Installing dependencies, Searching codebase\n\n\(trimmed)"
                ]
            ]
        ]

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 4

        Task {
            defer {
                Task { @MainActor [weak self] in
                    self?.inFlight = false
                }
            }
            do {
                let (data, _) = try await fetchWithRetry(
                    request: request,
                    maxAttempts: 3,
                    baseDelay: 1.0
                )
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let content = json["content"] as? [[String: Any]],
                   let text = content.first?["text"] as? String {
                    let summary = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    completion(summary.isEmpty ? nil : summary)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }
    }

    /// Request a structured completion summary using Anthropic's streaming API.
    /// Calls `onPartial` with incremental updates as fields complete, then `onComplete` when done.
    /// Returns nil if LLM summaries are disabled or content is empty.
    @discardableResult
    func summarizeCompletionStreaming(
        terminalContent: String,
        onPartial: @escaping (CompletionSummary) -> Void,
        onComplete: @escaping (CompletionSummary?) -> Void
    ) -> URLSessionDataTask? {
        guard isEnabled else {
            onComplete(nil)
            return nil
        }

        let trimmed = String(terminalContent.suffix(3000))
        guard !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onComplete(nil)
            return nil
        }

        let prompt = """
        You just watched a terminal session where Claude Code was working. Based on the output below, respond with a JSON object containing exactly three fields:

        - "what_happened": 1-2 sentences summarizing what was accomplished. Plain language, no technical jargon — explain it like you're talking to a non-developer. Past tense, concise.
        - "what_needed": What the user needs to do next, or "Nothing — task complete" if done. Plain language.
        - "suggested_prompt": A short, specific follow-up the user could type next (e.g. "run the tests", "check the build", "open the app"). 2-6 words, imperative, no punctuation. If the task is fully complete with nothing obvious to do next, use null.

        CRITICAL: Respond with ONLY the raw JSON object. No markdown fences, no backticks, no extra text before or after.

        Terminal output:
        \(trimmed)
        """

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 200,
            "stream": true,
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 10

        // Invalidate any previous streaming session before creating a new one
        streamingSession?.invalidateAndCancel()

        let delegate = SSEStreamDelegate(request: request, onPartial: onPartial, onComplete: onComplete)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        streamingSession = session
        let task = session.dataTask(with: request)
        task.resume()
        return task
    }

    /// Instant heuristic summary based on keyword matching. No network call.
    /// Delegates to `ActivityCategory.classify(_:)` for the single shared implementation.
    func heuristicSummary(_ content: String) -> String? {
        ActivityCategory.classify(content).summary
    }
}

// MARK: - SSE Stream Delegate

/// URLSession delegate that parses Anthropic SSE streaming responses and incrementally
/// builds a CompletionSummary, calling back as each field completes.
/// Automatically retries on 5xx server errors with exponential backoff (up to 3 attempts).
private class SSEStreamDelegate: NSObject, URLSessionDataDelegate {
    private let onPartial: (CompletionSummary) -> Void
    private let onComplete: (CompletionSummary?) -> Void
    private var buffer = ""
    private var accumulatedText = ""
    private var didComplete = false

    /// Retry state for 5xx server errors.
    private let request: URLRequest
    private let maxRetryAttempts: Int = 3
    private var currentAttempt: Int = 0
    private var receivedServerError = false

    init(
        request: URLRequest,
        onPartial: @escaping (CompletionSummary) -> Void,
        onComplete: @escaping (CompletionSummary?) -> Void
    ) {
        self.request = request
        self.onPartial = onPartial
        self.onComplete = onComplete
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse, (500...599).contains(http.statusCode) {
            currentAttempt += 1
            if currentAttempt < maxRetryAttempts {
                receivedServerError = true
                // Cancel this request; retry after backoff in didCompleteWithError.
                completionHandler(.cancel)
                return
            }
        }
        receivedServerError = false
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buffer += chunk

        while let lineEnd = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<lineEnd])
            buffer = String(buffer[buffer.index(after: lineEnd)...])

            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { continue }

            guard let eventData = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any] else {
                continue
            }

            if let type = event["type"] as? String, type == "content_block_delta",
               let delta = event["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                accumulatedText += text
                emitPartial()
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // If we cancelled due to a 5xx, retry after exponential backoff.
        if receivedServerError {
            receivedServerError = false
            buffer = ""
            accumulatedText = ""
            let delay = 1.0 * pow(2.0, Double(currentAttempt - 1))
            let jitter = Double.random(in: 0...0.5)
            DispatchQueue.global().asyncAfter(deadline: .now() + delay + jitter) {
                let retryTask = session.dataTask(with: self.request)
                retryTask.resume()
            }
            return
        }

        guard !didComplete else { return }
        didComplete = true

        if error != nil {
            onComplete(nil)
            session.finishTasksAndInvalidate()
            return
        }

        let summary = parseCompletionSummary(from: accumulatedText)
        onComplete(summary)
        session.finishTasksAndInvalidate()
    }

    private func emitPartial() {
        var cleaned = accumulatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
        }

        let happened = extractJSONStringValue(from: cleaned, key: "what_happened")
        let needed = extractJSONStringValue(from: cleaned, key: "what_needed")
        let suggested = extractJSONStringValue(from: cleaned, key: "suggested_prompt")

        // Only emit when we have both required fields
        if let h = happened, let n = needed {
            onPartial(CompletionSummary(whatHappened: h, whatNeeded: n, suggestedPrompt: suggested))
        } else if let h = happened {
            // Have what_happened, still waiting on what_needed — emit with placeholder
            onPartial(CompletionSummary(whatHappened: h, whatNeeded: String(localized: "activity.completion.summarizing", defaultValue: "Summarizing..."), suggestedPrompt: nil))
        }
    }

    private func parseCompletionSummary(from text: String) -> CompletionSummary? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            if let firstNewline = cleaned.firstIndex(of: "\n") {
                cleaned = String(cleaned[cleaned.index(after: firstNewline)...])
            }
            if cleaned.hasSuffix("```") {
                cleaned = String(cleaned.dropLast(3))
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let jsonData = cleaned.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let happened = parsed["what_happened"] as? String,
              let needed = parsed["what_needed"] as? String else {
            let happened = extractJSONStringValue(from: cleaned, key: "what_happened")
            let needed = extractJSONStringValue(from: cleaned, key: "what_needed")
            if let h = happened, let n = needed {
                return CompletionSummary(whatHappened: h, whatNeeded: n, suggestedPrompt: extractJSONStringValue(from: cleaned, key: "suggested_prompt"))
            }
            return nil
        }

        let suggested = parsed["suggested_prompt"] as? String
        return CompletionSummary(whatHappened: happened, whatNeeded: needed, suggestedPrompt: suggested)
    }

    private func extractJSONStringValue(from json: String, key: String) -> String? {
        let pattern = "\"\(key)\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: json, range: NSRange(json.startIndex..., in: json)),
              let valueRange = Range(match.range(at: 1), in: json) else {
            return nil
        }
        return String(json[valueRange])
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
    }
}
