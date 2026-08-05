import Foundation
import Combine

// upstream: PR#6798 — Sources/Mobile/AgentChat/AgentChatSessionRegistry.swift
//                   + Sources/Mobile/AgentChat/AgentChatSessionRegistry+Lifecycle.swift
//                   + docs/agent-session-tracking-spec.md
//
// THE authority for "what is this surface's agent doing right now".
//
// Everything that used to answer that question in this fork answered it by
// reading terminal TEXT at 10Hz and hashing it. That is the layer upstream
// deleted on purpose (spec, "What gets deleted"), and this file is its
// replacement. Three inputs, in strict precedence:
//
//   1. HOOK EVENTS (authoritative). The agent's own lifecycle, delivered over
//      the socket, each carrying the surface token cmux injected into the
//      shell. `nextState` below is upstream's reducer, transcribed verbatim.
//   2. PROCESS EXIT (deterministic backstop). A `DispatchSourceProcess` on the
//      agent pid fires exactly when the process dies — crash, Ctrl-C, `/exit`,
//      closed terminal — so `ended` never depends on a SessionEnd hook
//      arriving. Replaces the 5-minute "active timeout" that used to be the
//      only way out of the fork's ACTIVE state.
//   3. TRANSCRIPT CORROBORATION (correction only). A completed assistant turn
//      observed in the agent's own JSONL can clear a stuck `working` when the
//      hook stream never emits Stop (the Claude weekly-limit case). It may
//      only CORRECT; it may never invent presence.
//
// Plus an observe floor (`applyObservedSessions`) that binds an agent found in
// the process table with no hooks installed. Presence proves presence, not
// idleness — hence `hasHookLifecycleState`.
//
// Threading: `@MainActor`, and it only ever applies small pre-parsed value
// mutations. Decoding, process-table walks and transcript reads all happen off
// the main actor before anything reaches here. Upstream principle 8.
@MainActor
final class AgentSessionRegistry: ObservableObject {

    static let shared = AgentSessionRegistry()

    /// Live state per surface UUID. The single thing UI consumers read.
    /// Republished as a whole map so a SwiftUI view can observe one object
    /// instead of subscribing per surface.
    @Published private(set) var stateBySurfaceID: [UUID: AgentSessionState] = [:]

    /// Monotonic version per surface, so a consumer can tell "changed" from
    /// "same value re-published".
    @Published private(set) var versionBySurfaceID: [UUID: Int] = [:]

    private var records: [String: AgentSessionRecord] = [:]
    private var sessionIDsBySurfaceID: [String: Set<String>] = [:]
    private var versionBySessionID: [String: Int] = [:]

    /// Binding-token aliases: a token an agent actually carries -> the real
    /// surface it belongs to. Written ONLY by `assertBinding`, i.e. only ever
    /// by the daemon that owns the mapping; never inferred here.
    ///
    /// This is what makes a daemon-owned session bindable at all. Its pane
    /// carries `CMUX_SURFACE_ID=<fadid-session-id>-0`, minted before any
    /// surface existed, so every hook event and every process-table row from
    /// inside it is stamped with a token this app would otherwise have to
    /// drop. With the alias asserted, those inputs re-key onto the real
    /// surface and the whole Gate 2 machine works unchanged.
    /// orchestrator #62
    private var surfaceAliases: [String: String] = [:]

    /// Per-session process-exit watchers, tagged with the pid they watch.
    /// `DispatchSourceProcess` (`.exit`) fires exactly when the agent dies, so
    /// the session flips to `.ended` deterministically without a `SessionEnd`
    /// hook and without polling `kill(pid, 0)` on every read. It is an event
    /// source, not a timer, and is cancellable.
    /// upstream: PR#6798 — Slice B
    private var exitWatchers: [String: (pid: Int, source: DispatchSourceProcess)] = [:]

    /// Called after every record mutation with the previous value (nil for a
    /// brand-new record), so owners derive deltas in one place instead of
    /// hand-maintained flags.
    /// upstream: PR#6798 — AgentChatSessionRegistry.onRecordChanged
    var onRecordChanged: ((AgentSessionRecord, _ previous: AgentSessionRecord?) -> Void)?

    private let corroborator = AgentTranscriptCorroborator()

    private init() {
        corroborator.onCompletedAssistantTurn = { [weak self] sessionID, at in
            Task { @MainActor in
                self?.noteAssistantTurnCompleted(sessionID: sessionID, at: at)
            }
        }
        // Observe floor. AgentPresence already walks the process table off the
        // main thread every 2s for the presence gate; this reuses that same
        // walk so a hookless agent still gets bound.
        // upstream: PR#6798 — observe-floor detection
        AgentPresence.shared.onObservedSessions = { [weak self] sessions in
            Task { @MainActor in
                self?.applyObservedSessions(sessions)
            }
        }
        // ...and pump it. The sink alone was not enough: the scan was only
        // ever kicked by the overlay's lifecycle poll, so a surface whose
        // overlay never polled had no floor at all. orchestrator #61
        AgentPresence.shared.startObserving()
    }

    // MARK: - Reads

    /// The live state of the agent bound to a surface, or `nil` when no agent
    /// has ever been bound to it.
    ///
    /// When several sessions share a surface (a resume mints a new session id
    /// while the predecessor is still `ended`), the highest-priority live one
    /// wins — needs-input over working over idle over ended.
    /// upstream: PR#6798 — ChatSessionDescriptor.openable ordering
    func state(surfaceID: UUID) -> AgentSessionState? {
        stateBySurfaceID[surfaceID]
    }

    /// The record backing a surface's current state, when there is one.
    func record(surfaceID: UUID) -> AgentSessionRecord? {
        bestRecord(surfaceKey: surfaceID.uuidString.uppercased())
    }

    /// All known records, most recent activity first.
    func allRecords() -> [AgentSessionRecord] {
        records.values.sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    // MARK: - The reducer

    /// Hook event -> next state. Transcribed verbatim from upstream, including
    /// the comments that explain the non-obvious cases; changing any arm here
    /// is changing upstream's model, not tuning ours.
    /// upstream: PR#6798 — AgentChatSessionRegistry.nextState
    nonisolated static func nextState(
        previous: AgentSessionState,
        event: AgentHookEvent
    ) -> AgentSessionState {
        if previous.isEnded, event.name != .sessionStart {
            return .ended
        }
        switch event.name {
        case .sessionStart:
            return .idle
        case .userPromptSubmit, .preToolUse, .postToolUse, .todoWrite:
            if case .working = previous { return previous }
            return .working(since: event.receivedAt)
        case .preCompact, .postCompact:
            // Compaction is lifecycle telemetry. It can occur while a session
            // is idle, so it must not create a synthetic working state.
            return previous
        case .permissionRequest, .askUserQuestion, .exitPlanMode, .notification:
            if case .needsInput = previous { return previous }
            return .needsInput(since: event.receivedAt)
        case .stop:
            return .idle
        case .subagentStart, .subagentStop:
            // Task subagent lifecycle says nothing about the parent
            // session's activity; keep the current state.
            return previous
        case .sessionEnd:
            return .ended
        }
    }

    // MARK: - Hook ingest

    /// Folds one hook event into the authority. This is the ONLY path that may
    /// set an authoritative state.
    ///
    /// - Parameter event: A decoded, surface-bound hook event.
    @discardableResult
    func noteHookEvent(_ event: AgentHookEvent) -> AgentSessionRecord {
        let sessionID = event.sessionID
        // A hook fired inside a daemon-owned session carries the token fadid
        // injected, not a surface UUID. Resolve it through the asserted alias
        // table before anything downstream sees it. orchestrator #62
        let boundSurfaceKey = event.surfaceID.flatMap { $0.isEmpty ? nil : resolveSurfaceKey($0) }
        let previous = records[sessionID]
            ?? adoptPendingRecord(for: event, surfaceKey: boundSurfaceKey)

        var record = previous ?? AgentSessionRecord(
            sessionID: sessionID,
            agentKind: event.agentKind,
            surfaceID: boundSurfaceKey,
            workspaceID: event.workspaceID?.uppercased(),
            workingDirectory: event.cwd,
            transcriptPath: nil,
            state: .idle,
            lastActivityAt: event.receivedAt
        )

        // The event is rewritten by the agent on every hook, so its non-nil
        // fields are fresher than the record's. Never keep a stale binding over
        // a present one.
        // upstream: PR#6798 — AgentChatSessionRecord.adoptBindings
        if let boundSurfaceKey {
            record.surfaceID = boundSurfaceKey
        }
        if let workspaceID = event.workspaceID, !workspaceID.isEmpty {
            record.workspaceID = workspaceID.uppercased()
        }
        if let cwd = event.cwd, !cwd.isEmpty {
            record.workingDirectory = cwd
        }
        if let transcriptPath = event.transcriptPath, !transcriptPath.isEmpty {
            record.transcriptPath = transcriptPath
        }
        // upstream: PR#6798 — only trust the hook-reported pid at SessionStart,
        // or to fill a binding we don't have yet. `agentPID` comes from the
        // hook's `$PPID`, which is only reliably the agent process at session
        // start; a wrapper process can report a different parent on later
        // hooks. Re-binding on every event let that thrash the exit watcher
        // (teardown + rebind per hook) and could flip a live session to
        // `ended` mid-run when the stale pid died.
        if let pid = event.agentPID, pid > 0,
            event.name == .sessionStart || record.pid == nil
        {
            record.pid = pid
        }

        record.setHookLifecycleState(Self.nextState(previous: record.state, event: event))
        record.lastActivityAt = max(record.lastActivityAt, event.receivedAt)

        storeRecord(record, replacing: previous, at: event.receivedAt)
        return record
    }

    /// A pending record was created by the observe floor or an OSC signal
    /// before the agent's first hook fired. The first hook carries the real
    /// session id, so fold the pending record's bindings into it and retire it.
    /// upstream: PR#6798 — the pending-alias / canonicalization path.
    private func adoptPendingRecord(
        for event: AgentHookEvent,
        surfaceKey: String?
    ) -> AgentSessionRecord? {
        guard let surfaceID = surfaceKey else { return nil }
        let pendingID = Self.pendingSessionID(surfaceKey: surfaceID)
        guard var pending = records[pendingID] else { return nil }
        removeRecord(sessionID: pendingID)
        pending = AgentSessionRecord(
            sessionID: event.sessionID,
            agentKind: event.agentKind,
            surfaceID: pending.surfaceID,
            workspaceID: pending.workspaceID,
            workingDirectory: pending.workingDirectory,
            transcriptPath: pending.transcriptPath,
            state: pending.state,
            hasHookLifecycleState: pending.hasHookLifecycleState,
            endedAt: pending.endedAt,
            lastActivityAt: pending.lastActivityAt,
            pid: pending.pid
        )
        return pending
    }

    // MARK: - Daemon-asserted bindings

    /// Accepts a binding `fadid` asserts for a surface attached to a session it
    /// supervises. Same standing as a hook-carried binding: it is the agent's
    /// owner reporting identity, not this app inferring it.
    ///
    /// It asserts IDENTITY, never ACTIVITY. The daemon knows which process is
    /// the agent; it does not know whether that agent is thinking. So a record
    /// with no hook lifecycle yet gets the presence floor (`idle`, unproven),
    /// and one that already has hook state keeps it — exactly the rule the
    /// observe floor follows.
    /// orchestrator #62
    func assertBinding(_ binding: AssertedAgentBinding) {
        let surfaceKey = binding.surfaceID.uppercased()

        // The alias is the load-bearing half: it is the token the supervised
        // agent actually carries, so every later hook and every process-table
        // row from that session re-keys onto this surface instead of being
        // dropped for having no resolvable binding.
        if let alias = binding.surfaceAlias?.uppercased(),
           !alias.isEmpty, alias != surfaceKey {
            surfaceAliases[alias] = surfaceKey
            rekeyRecords(fromSurfaceKey: alias, toSurfaceKey: surfaceKey)
        }

        // Prefer the agent's own session id. Until the daemon has discovered
        // one, use this surface's pending id so the first real hook retires it
        // through the ordinary canonicalization path.
        let sessionID = binding.sessionID.flatMap { $0.isEmpty ? nil : $0 }
            ?? Self.pendingSessionID(surfaceKey: surfaceKey)

        // A record the observe floor already minted for the same live pid on
        // this surface IS this session; adopt it rather than shadowing it.
        let previous = records[sessionID]
            ?? binding.agentPID.flatMap { boundRecord(surfaceKey: surfaceKey, pid: $0) }

        var record = previous ?? AgentSessionRecord(
            sessionID: sessionID,
            agentKind: binding.agentKind,
            surfaceID: surfaceKey,
            state: .idle,
            lastActivityAt: binding.assertedAt
        )
        if let previous, previous.sessionID != sessionID {
            // Re-key an adopted record onto the asserted session id.
            removeRecord(sessionID: previous.sessionID)
            record = AgentSessionRecord(
                sessionID: sessionID,
                agentKind: previous.agentKind,
                surfaceID: previous.surfaceID,
                workspaceID: previous.workspaceID,
                workingDirectory: previous.workingDirectory,
                transcriptPath: previous.transcriptPath,
                state: previous.state,
                hasHookLifecycleState: previous.hasHookLifecycleState,
                endedAt: previous.endedAt,
                lastActivityAt: previous.lastActivityAt,
                pid: previous.pid
            )
        }

        record.surfaceID = surfaceKey
        if let pid = binding.agentPID, pid > 0 { record.pid = pid }
        if let workspaceID = binding.workspaceID, !workspaceID.isEmpty {
            record.workspaceID = workspaceID.uppercased()
        }
        if let cwd = binding.cwd, !cwd.isEmpty { record.workingDirectory = cwd }
        if let transcriptPath = binding.transcriptPath, !transcriptPath.isEmpty {
            record.transcriptPath = transcriptPath
        }
        record.lastActivityAt = max(record.lastActivityAt, binding.assertedAt)

        // The daemon proved the process is alive right now, so a record that
        // had been ended under a predecessor pid is live again.
        if record.state.isEnded {
            record.setProcessObservedIdle()
            record.endedAt = nil
        } else if !record.hasHookLifecycleState {
            record.setProcessObservedIdle()
        }

        storeRecord(record, replacing: records[sessionID], at: Date())
    }

    /// Resolves a binding token to a surface key, through the asserted alias
    /// table. An unknown token is returned uppercased and unchanged — it is
    /// either already a surface UUID or it will fail to parse as one later,
    /// which is the loud drop we want.
    private func resolveSurfaceKey(_ token: String) -> String {
        let key = token.uppercased()
        return surfaceAliases[key] ?? key
    }

    /// Moves every record parked on an alias key onto the real surface. Covers
    /// the ordinary race where the observe floor saw the supervised agent
    /// before the daemon's assertion arrived.
    private func rekeyRecords(fromSurfaceKey alias: String, toSurfaceKey surfaceKey: String) {
        guard let ids = sessionIDsBySurfaceID[alias] else { return }
        for sessionID in ids {
            update(sessionID: sessionID) { $0.surfaceID = surfaceKey }
        }
    }

    /// The record on a surface currently bound to a given pid, if any.
    private func boundRecord(surfaceKey: String, pid: Int) -> AgentSessionRecord? {
        guard let ids = sessionIDsBySurfaceID[surfaceKey] else { return nil }
        return ids.compactMap { records[$0] }.first { $0.pid == pid }
    }

    // MARK: - Explicit agent signals (OSC 7777 / 7778)

    // This fork already had an explicit, agent-emitted signal channel before
    // upstream's hooks existed: Ghostty's OSC 7777 (task completion, with a
    // tier) and OSC 7778 (working start/stop). Those are NOT heuristics — the
    // agent deliberately emits them, exactly like a hook — so they are folded
    // in through the same reducer rather than deleted. They map onto upstream's
    // vocabulary: 7778;start == UserPromptSubmit, 7778;stop / 7777 == Stop.
    //
    // They carry no session id, so they attach to the surface's current record,
    // or mint a pending one.

    /// OSC 7778 `start`.
    func noteExplicitWorkingStarted(surfaceID: UUID, at when: Date = Date()) {
        applySyntheticEvent(name: .userPromptSubmit, surfaceID: surfaceID, at: when)
    }

    /// OSC 7778 `stop` and OSC 7777 (task completion).
    func noteExplicitWorkingStopped(surfaceID: UUID, at when: Date = Date()) {
        applySyntheticEvent(name: .stop, surfaceID: surfaceID, at: when)
    }

    private func applySyntheticEvent(name: AgentHookEvent.Name, surfaceID: UUID, at when: Date) {
        let key = surfaceID.uuidString.uppercased()
        let sessionID = bestRecord(surfaceKey: key)?.sessionID ?? Self.pendingSessionID(surfaceKey: key)
        let event = AgentHookEvent(
            sessionID: sessionID,
            name: name,
            source: "claude",
            surfaceID: key,
            agentPID: nil,
            receivedAt: when
        )
        noteHookEvent(event)
        fillMissingPID(sessionID: sessionID, surfaceKey: key)
    }

    /// An OSC-bound session carries no pid, because OSC 7777/7778 is a byte in
    /// the terminal stream — it has no `$PPID` to fold in the way a hook
    /// command does. Without a pid BOTH deterministic exit paths opt out
    /// (`syncProcessExitWatch` arms nothing, and the observe-floor reap is
    /// guarded on `pid != nil`), so `ended` could never fire for a session
    /// that never saw a hook. ADR-0006 sells process-exit as the backstop that
    /// replaced the 5-minute ACTIVE timeout precisely for the no-hooks case,
    /// so that hole was in the exact configuration the backstop covers.
    ///
    /// The presence layer already answers "which pid is the agent on this
    /// surface". Ask it — off the main actor, because it walks the process
    /// table — and fill the gap.
    /// orchestrator #60
    private func fillMissingPID(sessionID: String, surfaceKey: String) {
        guard let record = records[sessionID], record.pid == nil, !record.state.isEnded else {
            return
        }
        Task.detached(priority: .utility) { [weak self] in
            guard let pid = AgentPresence.shared.liveAgentPID(surfaceKey: surfaceKey) else { return }
            await MainActor.run { [weak self] in
                self?.update(sessionID: sessionID) { record in
                    // Never overwrite a pid someone authoritative already set.
                    if record.pid == nil { record.pid = pid }
                }
            }
        }
    }

    /// Synthetic id for a session bound to a surface before any hook has named
    /// it. Retired the moment a real hook arrives.
    /// upstream: PR#6798 — isPendingClaudeSessionID
    static func pendingSessionID(surfaceKey: String) -> String {
        "pending-\(surfaceKey)"
    }

    static func isPendingSessionID(_ id: String) -> Bool {
        id.hasPrefix("pending-")
    }

    // MARK: - Observe floor

    /// Folds process-table detections in: create a record for any session not
    /// already known, and refresh bindings on one that is.
    ///
    /// A detection proves the agent exists and which surface owns it. It does
    /// NOT prove idleness, so it only sets state on a record that has never had
    /// a hook lifecycle — `hasHookLifecycleState` guards that.
    /// upstream: PR#6798 — AgentChatSessionRegistry.applyObservedSessions
    func applyObservedSessions(_ observed: [ObservedAgentSession]) {
        let now = Date()
        var seenSurfaceKeys = Set<String>()

        for session in observed {
            // A supervised agent's process environment carries the token fadid
            // injected, not a surface UUID. Resolve it through the asserted
            // alias table so the floor binds it too. orchestrator #62
            let surfaceKey = resolveSurfaceKey(session.surfaceID)
            seenSurfaceKeys.insert(surfaceKey)

            // One live pid is one session: if this surface already has a record
            // bound to this pid (the daemon asserted it, or an earlier scan
            // minted it), refresh THAT rather than minting a rival pending one.
            let sessionID = session.sessionID
                ?? boundRecord(surfaceKey: surfaceKey, pid: session.pid)?.sessionID
                ?? Self.pendingSessionID(surfaceKey: surfaceKey)
            let previous = records[sessionID]

            if var record = previous {
                // A sample taken before the record ended must not revive it.
                // upstream: PR#6798 — endedAt guard
                if let endedAt = record.endedAt, session.sampledAt <= endedAt { continue }
                var changed = false
                if record.pid != session.pid { record.pid = session.pid; changed = true }
                if record.surfaceID == nil { record.surfaceID = surfaceKey; changed = true }
                if record.workingDirectory == nil, session.workingDirectory != nil {
                    record.workingDirectory = session.workingDirectory
                    changed = true
                }
                if record.transcriptPath == nil, session.transcriptPath != nil {
                    record.transcriptPath = session.transcriptPath
                    changed = true
                }
                if record.state.isEnded {
                    // The process is demonstrably alive again under this
                    // surface: the earlier `ended` was about a predecessor pid.
                    record.setProcessObservedIdle()
                    record.endedAt = nil
                    changed = true
                }
                guard changed else { continue }
                record.lastActivityAt = max(record.lastActivityAt, session.sampledAt)
                storeRecord(record, replacing: previous, at: now)
            } else {
                var record = AgentSessionRecord(
                    sessionID: sessionID,
                    agentKind: session.agentKind,
                    surfaceID: surfaceKey,
                    workspaceID: session.workspaceID?.uppercased(),
                    workingDirectory: session.workingDirectory,
                    transcriptPath: session.transcriptPath,
                    state: .idle,
                    lastActivityAt: session.sampledAt,
                    pid: session.pid
                )
                record.setProcessObservedIdle()
                storeRecord(record, replacing: nil, at: now)
            }
        }

        // A surface whose agent is no longer in the process table ends, unless
        // its exit watcher is already handling it. This is the same fact the
        // watcher delivers, just from the other direction — it covers the case
        // where the app was not running when the process died.
        for (surfaceKey, sessionIDs) in sessionIDsBySurfaceID where !seenSurfaceKeys.contains(surfaceKey) {
            for sessionID in sessionIDs {
                guard let record = records[sessionID], !record.state.isEnded, record.pid != nil else { continue }
                update(sessionID: sessionID) { $0.state = .ended }
            }
        }
    }

    // MARK: - Transcript corroboration

    /// A transcript tail can observe a completed assistant turn even when the
    /// agent hook stream never emits Stop (Claude weekly-limit replies do this).
    /// Use that transcript fact ONLY to clear an active working state; later
    /// hooks remain authoritative and can move the session back to working or
    /// needs-input.
    /// upstream: PR#6798 — AgentChatSessionRegistry.noteAssistantTurnCompleted
    func noteAssistantTurnCompleted(sessionID: String, at timestamp: Date) {
        update(sessionID: sessionID) { record in
            guard case .working = record.state else { return }
            record.setTranscriptObservedIdle()
            if timestamp > record.lastActivityAt {
                record.lastActivityAt = timestamp
            }
        }
    }

    // MARK: - Mutation plumbing

    /// Applies a mutation to one record and republishes.
    func update(sessionID: String, _ mutate: (inout AgentSessionRecord) -> Void) {
        guard let previous = records[sessionID] else { return }
        var record = previous
        mutate(&record)
        guard record != previous else { return }
        storeRecord(record, replacing: previous, at: Date())
    }

    /// Stamps the next monotonic version onto a record before it is stored. All
    /// write paths route through this, so no externally visible change ever
    /// ships with a stale or unchanged version. A counter, not a hash, so
    /// strict monotonicity holds even when a change reverts a field.
    /// upstream: PR#6798 — AgentChatSessionRegistry.stampVersion
    private func stampVersion(_ record: inout AgentSessionRecord) {
        let next = (versionBySessionID[record.sessionID] ?? 0) + 1
        versionBySessionID[record.sessionID] = next
        record.version = next
    }

    /// Records when a session entered or left `ended`, so a stale observation
    /// cannot revive it.
    /// upstream: PR#6798 — AgentChatSessionRegistry.stampLifecycleTransition
    private func stampLifecycleTransition(
        previous: AgentSessionRecord?,
        current: inout AgentSessionRecord,
        at transitionAt: Date
    ) {
        let wasEnded = previous?.state.isEnded ?? false
        if current.state.isEnded {
            if wasEnded {
                current.endedAt = current.endedAt ?? previous?.endedAt ?? transitionAt
            } else {
                current.endedAt = transitionAt
            }
        } else {
            current.endedAt = nil
        }
    }

    private func storeRecord(
        _ record: AgentSessionRecord,
        replacing previous: AgentSessionRecord?,
        at transitionAt: Date
    ) {
        var stored = record
        stampLifecycleTransition(previous: previous, current: &stored, at: transitionAt)
        stampVersion(&stored)
        records[stored.sessionID] = stored

        syncProcessExitWatch(for: stored)
        syncTranscriptCorroboration(for: stored)
        rebuildSurfaceIndex()
        onRecordChanged?(stored, previous)
    }

    private func removeRecord(sessionID: String) {
        records.removeValue(forKey: sessionID)
        versionBySessionID.removeValue(forKey: sessionID)
        exitWatchers[sessionID]?.source.cancel()
        exitWatchers.removeValue(forKey: sessionID)
        corroborator.stop(sessionID: sessionID)
        rebuildSurfaceIndex()
    }

    // MARK: - Indexes

    private func rebuildSurfaceIndex() {
        var bySurface: [String: Set<String>] = [:]
        for record in records.values {
            guard let surfaceID = record.surfaceID else { continue }
            bySurface[surfaceID, default: []].insert(record.sessionID)
        }
        sessionIDsBySurfaceID = bySurface

        var states: [UUID: AgentSessionState] = [:]
        var versions: [UUID: Int] = [:]
        for (surfaceKey, _) in bySurface {
            guard let uuid = UUID(uuidString: surfaceKey),
                  let best = bestRecord(surfaceKey: surfaceKey) else { continue }
            states[uuid] = best.state
            versions[uuid] = best.version
        }
        if states != stateBySurfaceID { stateBySurfaceID = states }
        if versions != versionBySurfaceID { versionBySurfaceID = versions }
    }

    /// The session that should speak for a surface: highest live priority, then
    /// most recent activity. A dead session never shadows a live one.
    /// upstream: PR#6798 — ChatSessionDescriptor.openable
    private func bestRecord(surfaceKey: String) -> AgentSessionRecord? {
        guard let ids = sessionIDsBySurfaceID[surfaceKey], !ids.isEmpty else { return nil }
        let candidates = ids.compactMap { records[$0] }
        return candidates.min { lhs, rhs in
            let lp = AgentSessionState.selectionPriority(lhs.state)
            let rp = AgentSessionState.selectionPriority(rhs.state)
            if lp != rp { return lp < rp }
            return lhs.lastActivityAt > rhs.lastActivityAt
        }
    }

    // MARK: - Process-exit backstop

    /// Reconciles the session's exit watcher with its current pid. Called from
    /// every store path, so a watcher exists exactly while a session has a live
    /// pid and is cancelled when the pid changes, clears, or the session ends.
    /// Idempotent: a no-op when already watching the right pid.
    ///
    /// A process that is already gone at registration (the app was off while it
    /// died) would never produce an `.exit` event, so that case ends the
    /// session on a fresh main-actor turn rather than registering a watcher.
    /// upstream: PR#6798 — AgentChatSessionRegistry.syncProcessExitWatch
    private func syncProcessExitWatch(for record: AgentSessionRecord) {
        let sessionID = record.sessionID
        if let existing = exitWatchers[sessionID], existing.pid == record.pid {
            return
        }
        exitWatchers[sessionID]?.source.cancel()
        exitWatchers[sessionID] = nil
        guard !record.state.isEnded, let pid = record.pid else { return }

        // ESRCH means the process is already gone; EPERM means it exists but is
        // not signalable, which still counts as alive.
        if kill(pid_t(pid), 0) != 0, errno == ESRCH {
            Task { @MainActor [weak self] in
                self?.handleProcessExit(sessionID: sessionID, pid: pid)
            }
            return
        }

        let source = DispatchSource.makeProcessSource(
            identifier: pid_t(pid),
            eventMask: .exit,
            queue: .global(qos: .utility)
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.handleProcessExit(sessionID: sessionID, pid: pid)
            }
        }
        exitWatchers[sessionID] = (pid: pid, source: source)
        source.resume()
    }

    /// The watched pid died. Before ending the session, re-check the surface's
    /// process tree off-main: the dead pid may have been a launcher or shim
    /// (`node`, a subrouter) while the real agent still runs, in which case
    /// re-bind to the live agent pid instead of ending. Ignores a stale fire
    /// (the session may have resumed under a new pid, `claude --resume`).
    /// `ended` is retained; only the watcher is torn down.
    /// upstream: PR#6798 — AgentChatSessionRegistry.handleProcessExit
    private func handleProcessExit(sessionID: String, pid: Int) {
        guard let record = records[sessionID], record.pid == pid, !record.state.isEnded else {
            return
        }
        guard let surfaceID = record.surfaceID else {
            update(sessionID: sessionID) { $0.state = .ended }
            return
        }

        Task.detached(priority: .utility) { [weak self] in
            let livePID = AgentPresence.shared.liveAgentPID(surfaceKey: surfaceID)
            await MainActor.run { [weak self] in
                guard let self,
                      let current = self.records[sessionID],
                      current.pid == pid,
                      !current.state.isEnded else { return }
                if let livePID, livePID != pid {
                    // Real agent still alive under the surface: re-bind to it
                    // (this re-arms the exit watcher on the real agent pid).
                    self.update(sessionID: sessionID) { $0.pid = livePID }
                } else {
                    self.update(sessionID: sessionID) { $0.state = .ended }
                }
            }
        }
    }

    // MARK: - Transcript watch plumbing

    /// Corroboration is only worth running while a session could be stuck: it
    /// needs a recorded transcript path and an active `working` state.
    private func syncTranscriptCorroboration(for record: AgentSessionRecord) {
        guard let path = record.transcriptPath, record.state.isWorking else {
            corroborator.stop(sessionID: record.sessionID)
            return
        }
        corroborator.watch(sessionID: record.sessionID, transcriptPath: path)
    }

    // MARK: - Debug

    #if DEBUG
    var debugSummary: [String] {
        allRecords().map { record in
            "\(record.sessionID.prefix(8)) \(record.state.label) "
                + "surface=\(record.surfaceID?.prefix(8) ?? "-") "
                + "pid=\(record.pid.map(String.init) ?? "-") "
                + "hooks=\(record.hasHookLifecycleState ? 1 : 0) v\(record.version)"
        }
    }

    /// Daemon-asserted binding aliases, as `alias -> surface`. Out-of-process
    /// evidence that the #62 handshake actually landed.
    var debugSurfaceAliases: [String: String] { surfaceAliases }
    #endif
}
