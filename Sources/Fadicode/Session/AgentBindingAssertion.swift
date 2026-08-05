import Foundation

// orchestrator #62 — the seam between Gate 2 (session-state correctness) and
// Gate 3 (durability).
//
// Gate 2 binds an agent to a surface by injecting `CMUX_SURFACE_ID` into the
// shell the surface spawns, so any `claude` started there inherits the token.
// Gate 3 attaches a surface to a session `fadid` already started, so the agent
// was spawned by the tmux server long before that surface existed. It cannot
// inherit a variable that did not exist yet, and `tmux setenv` after the fact
// only reaches FUTURE children — never the running agent.
//
// So the app cannot derive this binding. It does not follow that it should
// guess: the daemon already owns the authoritative mapping (it spawned the
// session, it holds `registry.json`, it can see the pid inside the pane). The
// fix is a report, not a heuristic. Two facts, two owners:
//
//   * only the APP knows which surface ran `tmux -L fadi attach -t fadi/<id>`,
//   * only the DAEMON knows the agent's pid, transcript and session id.
//
// The app reports the first over fadid's UDS API (`FadiDaemonAttach`), the
// daemon asserts the second back over this app's own control socket as
// `agent_bind <json>`, and the registry accepts the assertion with the same
// standing as a hook-carried binding. An assertion with no surface is dropped
// loudly, exactly like an unbound hook event (upstream principle 3).

/// The binding `fadid` asserts for a surface attached to a supervised session.
struct AssertedAgentBinding: Sendable, Equatable {

    /// This app's own surface UUID string — the binding key.
    let surfaceID: String

    /// The `CMUX_SURFACE_ID` the supervised pane actually carries
    /// (`<daemon-session-id>-0`). Not a surface id and never can be: the pane
    /// predates the surface. It is the token every hook event and every
    /// process-table row from inside that session is stamped with, so the
    /// registry keeps it as an ALIAS and re-keys those inputs onto
    /// `surfaceID` rather than dropping them.
    let surfaceAlias: String?

    /// The fadid session id (`registry.json` `id`).
    let daemonSessionID: String

    /// The agent's own session id, when the daemon has discovered it. Absent
    /// until Claude Code has written an attributable transcript.
    let sessionID: String?

    /// The live agent pid inside the supervised pane. This is the field that
    /// makes the deterministic exit backstop reachable for a session the app
    /// did not spawn.
    let agentPID: Int?

    /// Absolute transcript JSONL path. The daemon only asserts one it has
    /// stat'd — a path we made up would be the newest-file-by-mtime guess
    /// upstream deleted, wearing a nicer hat.
    let transcriptPath: String?

    let cwd: String?
    let workspaceID: String?
    let source: String
    let assertedAt: Date

    var agentKind: AgentKind { AgentKind(source: source) }
}

// MARK: - Wire decoding

extension AssertedAgentBinding: Decodable {

    private enum CodingKeys: String, CodingKey {
        case surfaceID = "surface_id"
        case surfaceAlias = "surface_alias"
        case daemonSessionID = "daemon_session_id"
        case sessionID = "session_id"
        case agentPID = "agent_pid"
        case transcriptPath = "transcript_path"
        case cwd
        case workspaceID = "workspace_id"
        case source = "_source"
        case assertedAt = "_received_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        surfaceID = try c.decode(String.self, forKey: .surfaceID)
        surfaceAlias = try c.decodeIfPresent(String.self, forKey: .surfaceAlias)
        daemonSessionID = try c.decode(String.self, forKey: .daemonSessionID)
        sessionID = try c.decodeIfPresent(String.self, forKey: .sessionID)
        agentPID = try c.decodeIfPresent(Int.self, forKey: .agentPID)
        transcriptPath = try c.decodeIfPresent(String.self, forKey: .transcriptPath)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        workspaceID = try c.decodeIfPresent(String.self, forKey: .workspaceID)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "claude"
        if let seconds = try? c.decodeIfPresent(Double.self, forKey: .assertedAt) {
            assertedAt = Date(timeIntervalSince1970: seconds)
        } else {
            assertedAt = Date()
        }
    }

    /// Decodes one newline-free JSON payload.
    ///
    /// MUST be called off the main actor, like every decode in this subsystem.
    static func decode(_ json: Data) throws -> AssertedAgentBinding {
        try JSONDecoder().decode(AssertedAgentBinding.self, from: json)
    }
}

// MARK: - Socket ingress

/// Handles the `agent_bind` socket verb.
///
/// Deliberately shaped exactly like `AgentHookIngest`: decode off the socket
/// thread, hand one small value to the main actor, and refuse anything that
/// would require a guess.
enum AgentBindingIngest {

    /// - Parameter payload: The raw JSON argument, as `fadid` emitted it.
    /// - Returns: A socket response line.
    static func handle(payload: String) -> String {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "ERROR: Missing binding payload — usage: agent_bind <json>"
        }
        guard let data = trimmed.data(using: .utf8) else {
            return "ERROR: Binding payload is not valid UTF-8"
        }

        let binding: AssertedAgentBinding
        do {
            binding = try AssertedAgentBinding.decode(data)
        } catch {
            return "ERROR: Unrecognized binding payload (\(error))"
        }

        // The surface id must be a real surface UUID. The whole point of this
        // verb is that the daemon reports the app's own identifier back to it;
        // anything else is the guess this exists to delete.
        guard UUID(uuidString: binding.surfaceID) != nil else {
            return "ERROR: Binding surface_id is not a surface UUID (\(binding.surfaceID))"
        }
        guard !binding.daemonSessionID.isEmpty else {
            return "ERROR: Binding has no daemon_session_id"
        }

        DispatchQueue.main.async {
            AgentSessionRegistry.shared.assertBinding(binding)
        }
        return "OK: bound \(binding.surfaceID) -> \(binding.daemonSessionID)"
            + (binding.agentPID.map { " pid=\($0)" } ?? "")
    }
}
