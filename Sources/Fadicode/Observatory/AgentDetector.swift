import Foundation

/// Detects AI agent type from terminal content using heuristics.
/// No process tree walking — purely content-based for stability.
struct AgentDetector {

    /// Detect agent type from terminal output content.
    static func detectFromContent(_ content: String) -> AgentType {
        let lastChunk = String(content.suffix(3000))

        // Claude Code: look for characteristic patterns
        if lastChunk.contains("Claude Code")
            || lastChunk.contains("claude-code")
            || lastChunk.contains("⠋") || lastChunk.contains("⠙") || lastChunk.contains("⠹")
            || lastChunk.contains("⠸") || lastChunk.contains("⠼") || lastChunk.contains("⠴")
            || lastChunk.contains("⠦") || lastChunk.contains("⠧") || lastChunk.contains("⠇")
            || lastChunk.contains("⠏")
            || lastChunk.contains("Read tool") || lastChunk.contains("Write tool")
            || lastChunk.contains("Edit tool") || lastChunk.contains("Bash tool")
            || lastChunk.contains("Grep tool") || lastChunk.contains("Glob tool")
            || lastChunk.contains("Task tool")
            || lastChunk.contains("╭─") || lastChunk.contains("╰─")
        {
            return .claudeCode
        }

        // Codex: look for codex prompt
        if lastChunk.contains("codex>") || lastChunk.contains("codex ") {
            return .codex
        }

        // Aider: look for aider prompt
        if lastChunk.contains("aider>") || lastChunk.contains("aider ") || lastChunk.contains("Aider v") {
            return .aider
        }

        // OpenCode: look for opencode patterns
        if lastChunk.contains("opencode>") || lastChunk.contains("opencode ") {
            return .opencode
        }

        return .none
    }
}
