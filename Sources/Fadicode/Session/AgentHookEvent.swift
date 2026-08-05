import Foundation

// upstream: PR#6798 — Packages/macOS/CMUXAgentLaunch/Sources/CMUXAgentLaunch/
// Workstream/WorkstreamEvent.swift
//
// The wire frame an agent's hook command posts to the app socket. Field names
// and raw values are copied EXACTLY from upstream (which in turn mirrors Vibe
// Island's hook payload) so an existing `cmux hooks claude <event>` payload,
// or a Claude Code `settings.json` hook that pipes its stdin straight through,
// passes untouched.
//
// This is the one and only channel that moves the session state machine.
// Upstream's principle 2: "Deterministic binding, no heuristics." The event
// carries `surface_id` (inherited from the shell env cmux itself injected), so
// it maps to exactly one surface with no guessing.
//
// Narrowed vs upstream: `tool_input` (an arbitrary JSON blob), the OpenCode
// request id and the dynamic extra-field capture are dropped. This fork has no
// AnyJSON type and no consumer for them.

/// A single agent lifecycle event, already bound to a surface.
struct AgentHookEvent: Sendable, Equatable {

    /// Hook event discriminator. Raw values match the strings upstream's hook
    /// wrappers and Claude Code's own `hook_event_name` already emit, so no
    /// translation layer is needed.
    /// upstream: PR#6798 — WorkstreamEvent.HookEventName
    enum Name: String, Codable, Sendable, Equatable, CaseIterable {
        case sessionStart = "SessionStart"
        case sessionEnd = "SessionEnd"
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        /// Compaction is about to start.
        case preCompact = "PreCompact"
        /// Compaction completed.
        case postCompact = "PostCompact"
        case permissionRequest = "PermissionRequest"
        case askUserQuestion = "AskUserQuestion"
        case exitPlanMode = "ExitPlanMode"
        case todoWrite = "TodoWrite"
        case stop = "Stop"
        case subagentStart = "SubagentStart"
        case subagentStop = "SubagentStop"
        case notification = "Notification"
    }

    let sessionID: String
    let name: Name
    /// `_source` on the wire: which agent runtime fired the hook.
    let source: String
    let workspaceID: String?
    /// The binding key. Inherited from `CMUX_SURFACE_ID` in the shell env.
    let surfaceID: String?
    let transcriptPath: String?
    let cwd: String?
    let toolName: String?
    /// `_ppid` on the wire. A hook command is spawned BY the agent, so its
    /// parent pid is the agent's pid — which is what the exit watcher needs.
    /// upstream: PR#6798 — the store records the same value as the session pid.
    let agentPID: Int?
    let receivedAt: Date

    var agentKind: AgentKind { AgentKind(source: source) }

    init(
        sessionID: String,
        name: Name,
        source: String,
        workspaceID: String? = nil,
        surfaceID: String? = nil,
        transcriptPath: String? = nil,
        cwd: String? = nil,
        toolName: String? = nil,
        agentPID: Int? = nil,
        receivedAt: Date = Date()
    ) {
        self.sessionID = sessionID
        self.name = name
        self.source = source
        self.workspaceID = workspaceID
        self.surfaceID = surfaceID
        self.transcriptPath = transcriptPath
        self.cwd = cwd
        self.toolName = toolName
        self.agentPID = agentPID
        self.receivedAt = receivedAt
    }
}

// MARK: - Wire decoding

extension AgentHookEvent: Decodable {

    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case name = "hook_event_name"
        case source = "_source"
        case workspaceID = "workspace_id"
        case surfaceID = "surface_id"
        case transcriptPath = "transcript_path"
        case cwd
        case toolName = "tool_name"
        case agentPID = "_ppid"
        case receivedAt = "_received_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(String.self, forKey: .sessionID)
        name = try c.decode(Name.self, forKey: .name)
        // `_source` is optional in practice: a raw Claude Code hook payload
        // piped straight through has no cmux-added fields. Default to claude,
        // which is the only runtime this fork binds today.
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "claude"
        workspaceID = try c.decodeIfPresent(String.self, forKey: .workspaceID)
        surfaceID = try c.decodeIfPresent(String.self, forKey: .surfaceID)
        transcriptPath = try c.decodeIfPresent(String.self, forKey: .transcriptPath)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        toolName = try c.decodeIfPresent(String.self, forKey: .toolName)
        agentPID = try c.decodeIfPresent(Int.self, forKey: .agentPID)
        if let seconds = try? c.decodeIfPresent(Double.self, forKey: .receivedAt) {
            receivedAt = Date(timeIntervalSince1970: seconds)
        } else {
            receivedAt = Date()
        }
    }

    /// Decodes one newline-free JSON payload.
    ///
    /// MUST be called off the main actor. Upstream principle 8: no JSON decode
    /// on the main thread in this subsystem.
    ///
    /// - Parameter json: The raw payload bytes.
    /// - Returns: The decoded event.
    static func decode(_ json: Data) throws -> AgentHookEvent {
        try JSONDecoder().decode(AgentHookEvent.self, from: json)
    }
}
