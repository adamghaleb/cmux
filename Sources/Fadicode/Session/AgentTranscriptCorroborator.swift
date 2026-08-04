import Foundation

// upstream: PR#6798 — Sources/Mobile/AgentChat/AgentChatTranscriptTailer.swift
//                   + AgentChatTranscriptService.completedAssistantTurnTimestamp
//
// The transcript backstop from upstream's reliability model:
//
//   "Transcript corroboration. The agent's own transcript JSONL is a reliable
//    record (unlike titles). A completed assistant turn observed in the tail
//    can clear a stuck `working`. Used only to correct, never to invent
//    presence."   — docs/agent-session-tracking-spec.md
//
// It exists for one real failure: Claude replies to a weekly-limit message
// without ever firing a Stop hook, so the session would sit in `working`
// forever. Note what it is NOT allowed to do — it can only move a session that
// we already believe is working to idle. It can never create a session, never
// claim presence, and never override a later hook.
//
// Only the file the agent itself REPORTED (`transcript_path` on the hook
// payload) is ever read. Upstream deleted newest-file-by-mtime scanning on
// purpose and this must not reintroduce it.
//
// Threading: everything here runs on a private utility queue. Upstream
// principle 8 — no file I/O and no JSONL parsing on the main thread.
final class AgentTranscriptCorroborator: @unchecked Sendable {

    /// Fired on the corroborator's own queue when a batch of newly appended
    /// transcript lines represents a COMPLETED assistant turn.
    var onCompletedAssistantTurn: ((String, Date) -> Void)?

    private struct Watch {
        let path: String
        var offset: UInt64
        var inode: UInt64
        /// Bytes after the last newline in the previous read — a JSONL line can
        /// be observed half-written.
        var partial: Data
    }

    private let queue = DispatchQueue(label: "com.fadicode.transcript-corroborator", qos: .utility)
    private var watches: [String: Watch] = [:]
    private var timer: DispatchSourceTimer?

    /// How often the tail is re-read. Upstream tails via an actor driven by
    /// transcript growth; a 2s poll off the main thread is the cheap equivalent
    /// for a backstop whose whole job is unsticking a state that is already
    /// wrong. It matches upstream's own observe throttle.
    /// upstream: PR#6798 — AgentChatSessionRegistry.observeThrottleInterval = 2
    private let interval: TimeInterval = 2.0

    /// Starts (or refreshes) corroboration for one session.
    ///
    /// - Parameters:
    ///   - sessionID: The session to report against.
    ///   - transcriptPath: Absolute path the AGENT reported. Never guessed.
    func watch(sessionID: String, transcriptPath: String) {
        queue.async { [self] in
            if let existing = watches[sessionID], existing.path == transcriptPath { return }
            // Seed the offset at the current end of file: only turns that
            // complete from now on are evidence about the state we hold now.
            let end = Self.fileSize(transcriptPath) ?? 0
            watches[sessionID] = Watch(
                path: transcriptPath,
                offset: end,
                inode: Self.fileInode(transcriptPath) ?? 0,
                partial: Data()
            )
            startTimerIfNeeded()
        }
    }

    /// Stops corroborating a session.
    func stop(sessionID: String) {
        queue.async { [self] in
            watches.removeValue(forKey: sessionID)
            if watches.isEmpty {
                timer?.cancel()
                timer = nil
            }
        }
    }

    // MARK: - Tail loop

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(500))
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source
        source.resume()
    }

    private func tick() {
        for (sessionID, watch) in watches {
            guard let (lines, updated) = readAppendedLines(watch) else { continue }
            watches[sessionID] = updated
            guard !lines.isEmpty else { continue }
            if let completedAt = Self.completedAssistantTurnTimestamp(in: lines) {
                onCompletedAssistantTurn?(sessionID, completedAt)
            }
        }
    }

    /// Reads whatever was appended since the last tick. Handles rotation (the
    /// agent starting a new transcript file) by resetting the cursor, which is
    /// upstream's `didReset` case.
    private func readAppendedLines(_ watch: Watch) -> ([Data], Watch)? {
        var watch = watch
        guard let size = Self.fileSize(watch.path) else { return nil }
        let inode = Self.fileInode(watch.path) ?? 0

        if inode != watch.inode || size < watch.offset {
            // Rotated or truncated: the cursor is meaningless.
            watch.inode = inode
            watch.offset = 0
            watch.partial = Data()
        }
        guard size > watch.offset else { return ([], watch) }

        guard let handle = FileHandle(forReadingAtPath: watch.path) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: watch.offset)
        } catch {
            return nil
        }
        let chunk = handle.readData(ofLength: Int(min(size - watch.offset, 1 << 20)))
        guard !chunk.isEmpty else { return ([], watch) }
        watch.offset += UInt64(chunk.count)

        var buffer = watch.partial
        buffer.append(chunk)

        var lines: [Data] = []
        var start = buffer.startIndex
        let newline = UInt8(ascii: "\n")
        while let idx = buffer[start...].firstIndex(of: newline) {
            let line = buffer[start..<idx]
            if !line.isEmpty { lines.append(Data(line)) }
            start = buffer.index(after: idx)
        }
        watch.partial = Data(buffer[start...])
        return (lines, watch)
    }

    // MARK: - Turn completion

    /// Upstream's rule, transcribed onto raw Claude JSONL rows.
    ///
    /// Over the newly appended batch, look only at ASSISTANT rows:
    ///   * any tool-use content block in the batch means the agent is mid-turn
    ///     — return nil, this is NOT a completed turn;
    ///   * otherwise the latest assistant timestamp is the completion instant.
    ///
    /// upstream: PR#6798 — AgentChatTranscriptService.completedAssistantTurnTimestamp,
    /// which returns nil for `.toolUse / .terminal / .fileEdit /
    /// .permissionRequest / .question` and takes the max timestamp over
    /// `.prose / .thought / .unsupported`.
    static func completedAssistantTurnTimestamp(in lines: [Data]) -> Date? {
        var completedAt: Date?
        for line in lines {
            guard let object = try? JSONSerialization.jsonObject(with: line),
                  let row = object as? [String: Any],
                  let type = row["type"] as? String,
                  type == "assistant" else { continue }

            if Self.rowContainsToolUse(row) { return nil }
            guard let timestamp = Self.timestamp(from: row) else { continue }
            completedAt = max(completedAt ?? timestamp, timestamp)
        }
        return completedAt
    }

    private static func rowContainsToolUse(_ row: [String: Any]) -> Bool {
        guard let message = row["message"] as? [String: Any] else { return false }
        guard let content = message["content"] as? [[String: Any]] else { return false }
        return content.contains { ($0["type"] as? String) == "tool_use" }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func timestamp(from row: [String: Any]) -> Date? {
        guard let raw = row["timestamp"] as? String else { return nil }
        return isoFormatter.date(from: raw) ?? isoFormatterNoFraction.date(from: raw)
    }

    // MARK: - stat helpers

    private static func fileSize(_ path: String) -> UInt64? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return UInt64(st.st_size)
    }

    private static func fileInode(_ path: String) -> UInt64? {
        var st = stat()
        guard stat(path, &st) == 0 else { return nil }
        return UInt64(st.st_ino)
    }
}
