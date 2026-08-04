import Foundation

// upstream: PR#6798 — CLI/cmux.swift hook ingest + docs/agent-session-tracking-spec.md
//                     ("State source: hook events tied to the token")
//
// The socket ingress for agent hook events. Upstream's `cmux hooks <agent>
// <event>` writes the agent's stdin payload to the app socket; this fork's
// equivalent verb is:
//
//     agent_hook {"session_id":"…","hook_event_name":"PreToolUse", …}
//
// The hook process, not the app, holds the binding token: it inherits
// `CMUX_SURFACE_ID` from the surface's shell. The socket carries no ambient
// environment, so the hook command must fold that value into the payload it
// forwards. The recommended Claude Code settings entry, for every event name in
// `AgentHookEvent.Name`:
//
//   {"type": "command",
//    "command": "jq -c --arg s \"$CMUX_SURFACE_ID\" --arg p \"$PPID\" \
//                 '. + {surface_id:$s, _ppid:($p|tonumber)}' \
//                | xargs -0 -I{} cmux-send 'agent_hook {}'"}
//
// That keeps the binding deterministic — never a title, never an mtime.
// An event that arrives with no binding is dropped loudly (upstream principle 3:
// "no unreliable fallback"), because guessing which surface it belongs to is
// exactly the class of mistake this whole gate exists to remove.
//
// Threading: decoding happens on the socket thread (off the main actor), and
// only the decoded value crosses to `@MainActor`. Upstream principle 8, and
// this fork's own socket policy ("default to off-main handling" — CLAUDE.md).
enum AgentHookIngest {

    /// Handles one `agent_hook` socket command.
    ///
    /// - Parameters:
    ///   - payload: The raw JSON argument, exactly as the agent emitted it.
    ///   - environmentSurfaceID: `CMUX_SURFACE_ID` from the caller's environment,
    ///     used only when the payload itself carries no surface binding.
    /// - Returns: A socket response line.
    static func handle(payload: String, environmentSurfaceID: String? = nil) -> String {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "ERROR: Missing hook payload — usage: agent_hook <json>"
        }
        guard let data = trimmed.data(using: .utf8) else {
            return "ERROR: Hook payload is not valid UTF-8"
        }

        let event: AgentHookEvent
        do {
            event = try AgentHookEvent.decode(data)
        } catch {
            return "ERROR: Unrecognized hook payload (\(error))"
        }

        // Env fallback for the binding key. Upstream resolves in the order
        // explicit flags -> inherited env -> tty -> process tree; this fork has
        // the first two, and the observe floor covers the rest.
        let resolved: AgentHookEvent
        if event.surfaceID?.isEmpty == false {
            resolved = event
        } else if let fallback = environmentSurfaceID, !fallback.isEmpty {
            resolved = AgentHookEvent(
                sessionID: event.sessionID,
                name: event.name,
                source: event.source,
                workspaceID: event.workspaceID,
                surfaceID: fallback,
                transcriptPath: event.transcriptPath,
                cwd: event.cwd,
                toolName: event.toolName,
                agentPID: event.agentPID,
                receivedAt: event.receivedAt
            )
        } else {
            // Upstream principle 3: no unreliable fallback. An event with no
            // binding is dropped loudly rather than attributed by guesswork.
            return "ERROR: Hook event has no surface binding (set CMUX_SURFACE_ID or pass surface_id)"
        }

        DispatchQueue.main.async {
            AgentSessionRegistry.shared.noteHookEvent(resolved)
        }
        return "OK: \(resolved.name.rawValue) \(resolved.sessionID)"
    }
}
