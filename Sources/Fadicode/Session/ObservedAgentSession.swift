import Foundation

// upstream: PR#6798 — Sources/Mobile/AgentChat/AgentChatSessionRegistry+Lifecycle.swift
//
// "A coding-agent session discovered by observing the process table, with no
//  dependency on hooks firing. Identity (and, for codex, the transcript path)
//  comes from the agent's own argv, environment, or open transcript file, so a
//  session launched through any indirection (a subrouter, a wrapper) is still
//  found."
//
// This is upstream's OBSERVE FLOOR. It is what keeps the pet honest for an
// agent started before hooks were installed, or by a user who never ran
// `cmux hooks setup`. Crucially it proves PRESENCE and IDENTITY — never
// activity. A record built from an observation carries
// `hasHookLifecycleState == false` so it can never out-rank a real hook.
struct ObservedAgentSession: Sendable, Equatable {
    /// The agent's own session id when argv revealed it (`--session-id <uuid>`
    /// or `--resume <uuid>`); nil when the agent was started plainly, in which
    /// case the registry mints a pending id.
    let sessionID: String?
    let agentKind: AgentKind
    /// The binding key, read out of the process's inherited `CMUX_SURFACE_ID`.
    let surfaceID: String
    let workspaceID: String?
    let pid: Int
    let workingDirectory: String?
    /// Only knowable for agents that hold the transcript open; nil for Claude,
    /// whose transcript path arrives with the first hook.
    let transcriptPath: String?
    let sampledAt: Date

    init(
        sessionID: String?,
        agentKind: AgentKind,
        surfaceID: String,
        workspaceID: String? = nil,
        pid: Int,
        workingDirectory: String? = nil,
        transcriptPath: String? = nil,
        sampledAt: Date = Date()
    ) {
        self.sessionID = sessionID
        self.agentKind = agentKind
        self.surfaceID = surfaceID
        self.workspaceID = workspaceID
        self.pid = pid
        self.workingDirectory = workingDirectory
        self.transcriptPath = transcriptPath
        self.sampledAt = sampledAt
    }

    /// The same observation, re-stamped for the current scan. A cached probe
    /// still describes a process that is alive NOW, and `sampledAt` is what
    /// guards a record against being revived by a pre-`ended` sample.
    func resampled(at when: Date) -> ObservedAgentSession {
        ObservedAgentSession(
            sessionID: sessionID,
            agentKind: agentKind,
            surfaceID: surfaceID,
            workspaceID: workspaceID,
            pid: pid,
            workingDirectory: workingDirectory,
            transcriptPath: transcriptPath,
            sampledAt: when
        )
    }
}
