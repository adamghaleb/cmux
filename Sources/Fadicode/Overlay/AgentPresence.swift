import Foundation
import Darwin

// upstream: PR#6798 — deterministic agent-session binding.
//
// Upstream cmux replaced every "is an agent running here?" heuristic (terminal
// title matching, transcript mtime scans, content hashing) with a deterministic
// chain: explicit flags -> inherited env -> tty -> process tree. This file is a
// narrow transcription of the parts the Fadicode overlay actually needs.
//
// What we take from upstream:
//   * CMUX_SURFACE_ID as THE binding key, read out of a foreign process's
//     environment via sysctl(KERN_PROCARGS2).  (upstream: PR#6798,
//     CmuxTopSnapshotScopeCache.swift / CmuxTopProcessArguments.swift)
//   * The basename-first agent classifier, with argv needles allowed ONLY when
//     the host binary is a known script runner. Upstream's comment is
//     load-bearing: "The classifier matches by process basename, so only the
//     real agent binary matches (a `node …/codex` shim is named `node` and does
//     not)."  (upstream: PR#6798, TaskManagerTypes.swift)
//   * Positive scope probes are cached forever; negative probes get a TTL.
//     Cache key includes process start time so PID reuse invalidates itself.
//
// What we deliberately DON'T take (and why):
//   * Upstream expands the full process tree from surface-root PIDs. We don't
//     need to: the shell that Ghostty spawns already carries CMUX_SURFACE_ID
//     (see GhosttyTerminalView.swift, `env["CMUX_SURFACE_ID"] = id.uuidString`),
//     and environment is inherited by every descendant. So an agent launched by
//     hand inside that shell carries the same token. Matching env directly on
//     agent-shaped processes is equivalent for the presence question and costs
//     one sysctl per candidate instead of one per process on the machine.
//   * (Gate 2 update) The hook-driven busy/idle/needsInput state machine and
//     transcript corroboration now live in Sources/Fadicode/Session/. This file
//     stays the PRESENCE layer and additionally acts as upstream's OBSERVE
//     FLOOR: every scan publishes `[ObservedAgentSession]` so an agent running
//     without hooks is still bound to its surface. Presence proves presence,
//     never idleness — see AgentSessionRecord.hasHookLifecycleState.

// MARK: - Process arguments / environment

/// Reads argv + environment of an arbitrary same-user process.
/// upstream: PR#6798 — CmuxTopProcessArguments.swift (KERN_PROCARGS2 byte parser)
enum FadiProcArgs {

    struct Info {
        let argv: [String]
        let environment: [String: String]
    }

    /// KERN_PROCARGS2 layout:
    ///   [Int32 argc][exec_path\0][NUL padding][argv[0..argc)\0…][envp\0…]
    static func read(pid: Int32) -> Info? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }

        var argc: Int32 = 0
        withUnsafeMutableBytes(of: &argc) { dst in
            buffer.withUnsafeBytes { src in
                dst.copyMemory(from: UnsafeRawBufferPointer(rebasing: src[0..<MemoryLayout<Int32>.size]))
            }
        }
        guard argc >= 0 else { return nil }

        var cursor = MemoryLayout<Int32>.size

        // exec_path, then its NUL padding
        while cursor < size, buffer[cursor] != 0 { cursor += 1 }
        while cursor < size, buffer[cursor] == 0 { cursor += 1 }

        // argv
        var argv: [String] = []
        var consumed: Int32 = 0
        while cursor < size, consumed < argc {
            let start = cursor
            while cursor < size, buffer[cursor] != 0 { cursor += 1 }
            if cursor > start, let s = String(bytes: buffer[start..<cursor], encoding: .utf8) {
                argv.append(s)
            }
            cursor += 1 // skip NUL
            consumed += 1
        }

        // envp — everything remaining, as KEY=VALUE
        var environment: [String: String] = [:]
        while cursor < size {
            let start = cursor
            while cursor < size, buffer[cursor] != 0 { cursor += 1 }
            if cursor > start,
               let entry = String(bytes: buffer[start..<cursor], encoding: .utf8),
               let eq = entry.firstIndex(of: "=") {
                environment[String(entry[entry.startIndex..<eq])] = String(entry[entry.index(after: eq)...])
            }
            cursor += 1
        }

        return Info(argv: argv, environment: environment)
    }
}

// MARK: - Process enumeration

/// One row of the machine-wide process table.
/// upstream: PR#6798 — CmuxTopProcessEnumeration.swift
struct FadiProcessRow {
    let pid: Int32
    let parentPID: Int32
    /// `pbi_name` when populated (32 chars), else `pbi_comm` (16 chars, truncated).
    let name: String
    /// Process start time, used only as a cache-invalidation key against PID reuse.
    let startTimeKey: UInt64
}

enum FadiProcessTable {

    static func snapshot() -> [FadiProcessRow] {
        var capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        capacity += 64 // headroom for processes spawned between the two calls

        var pids = [pid_t](repeating: 0, count: Int(capacity))
        let byteCount = proc_listallpids(&pids, Int32(Int(capacity) * MemoryLayout<pid_t>.size))
        guard byteCount > 0 else { return [] }

        let count = Int(byteCount) / MemoryLayout<pid_t>.size
        var rows: [FadiProcessRow] = []
        rows.reserveCapacity(count)

        for index in 0..<count {
            let pid = pids[index]
            guard pid > 0 else { continue }

            var info = proc_bsdinfo()
            let expected = Int32(MemoryLayout<proc_bsdinfo>.size)
            let got = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expected)
            guard got == expected else { continue }

            let name = Self.string(from: info.pbi_name) ?? Self.string(from: info.pbi_comm) ?? ""
            guard !name.isEmpty else { continue }

            let startKey = (UInt64(info.pbi_start_tvsec) << 20) ^ UInt64(info.pbi_start_tvusec)
            rows.append(FadiProcessRow(pid: pid,
                                       parentPID: Int32(info.pbi_ppid),
                                       name: name,
                                       startTimeKey: startKey))
        }
        return rows
    }

    /// `pbi_name` / `pbi_comm` are fixed-size C char tuples; read them as a C string.
    private static func string<T>(from tuple: T) -> String? {
        var value = tuple
        return withUnsafeBytes(of: &value) { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let s = String(cString: base.assumingMemoryBound(to: CChar.self))
            return s.isEmpty ? nil : s
        }
    }
}

// MARK: - Agent presence

/// Deterministic answer to "is a real coding agent alive and bound to this surface?"
///
/// Replaces the old content-hash heuristic that inferred agent activity by
/// polling terminal TEXT at 10Hz — which fired on ordinary shell output and then
/// stayed stuck until a 5-minute timeout.
///
/// upstream: PR#6798
final class AgentPresence {

    static let shared = AgentPresence()

    /// Real agent binaries, matched on process basename.
    /// upstream: PR#6798 — basename match is deliberately first and authoritative.
    ///
    /// `claude.exe` is not a typo and is the case that actually matters on this
    /// machine: the npm install of Claude Code
    /// (`~/.npm-global/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe`)
    /// reports `claude.exe` as its process name. Its background helpers
    /// (`claude bg-pty-host`, `claude bg-spare`) report the same name and are
    /// intentionally counted — if a helper is alive the session is alive.
    /// Verified against a live process table, not assumed.
    private let agentBasenames: Set<String> = ["claude", "claude.exe"]

    /// Script hosts. Only for these are argv needles consulted, so that a
    /// `node …/claude/cli.js` install is still detected while unrelated node
    /// processes are not.
    private let scriptHosts: Set<String> = [
        "node", "bun", "deno", "npm", "npx", "pnpm", "yarn", "tsx"
    ]

    /// argv substrings that identify Claude Code running under a script host.
    private let agentArgvNeedles: [String] = [
        "@anthropic-ai/claude-code",
        "/claude/cli.js",
        ".claude/local/",
        "claude-code/cli.js"
    ]

    /// Full rescan throttle. Upstream uses ~2s; the old poll ran at 10Hz.
    private let rescanInterval: TimeInterval = 2.0

    /// Negative scope probes expire so a later `exec` is eventually attributed.
    /// Positive probes never expire — a discovered scope is stable.
    /// upstream: PR#6798 — CmuxTopSnapshotScopeCache.swift
    private let negativeTTL: TimeInterval = 10.0

    private struct ScopeEntry {
        let surfaceID: String?
        let isAgent: Bool
        let startTimeKey: UInt64
        let probedAt: Date
        /// The observe-floor row this probe produced, when it produced one.
        /// upstream: PR#6798 — ObservedAgentSession
        let observed: ObservedAgentSession?
    }

    private let lock = NSLock()
    private var scopeCache: [Int32: ScopeEntry] = [:]
    private var liveSurfaceIDs: Set<String> = []
    private var lastScan: Date = .distantPast
    /// Guards against piling up overlapping background scans.
    private var scanInFlight = false

    /// Last completed scan's observe-floor rows.
    /// upstream: PR#6798 — AgentChatSessionRegistry+ObserveScan
    private var lastObserved: [ObservedAgentSession] = []

    /// Called on the scan's background queue after every completed scan, with
    /// the full observe-floor snapshot. The session registry subscribes to this
    /// so an agent with no hooks installed is still bound to its surface.
    /// upstream: PR#6798 — observe-floor detection
    var onObservedSessions: (([ObservedAgentSession]) -> Void)?

    /// Self-driving scan pump. See `startObserving()`.
    private var pump: DispatchSourceTimer?

    private init() {}

    /// Starts pumping the process-table scan on a fixed cadence, independent of
    /// any view.
    ///
    /// The scan used to be kicked ONLY by `isAgentLive(surfaceID:)`, which is
    /// called from the overlay's lifecycle poll. That made the observe floor —
    /// the thing that binds an agent when no hooks are installed — conditional
    /// on an overlay actually polling, which does not happen for a surface
    /// whose window is not front, or before any overlay has mounted. Measured:
    /// a live interactive `claude` in a surface produced no registry record at
    /// all, because no scan had ever run.
    ///
    /// The floor is authority-layer infrastructure, not a view affordance, so
    /// it now drives itself. Idempotent; one timer per process.
    /// orchestrator #61
    func startObserving() {
        lock.lock()
        let alreadyRunning = pump != nil
        lock.unlock()
        guard !alreadyRunning else { return }

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: rescanInterval, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            self?.scheduleRefreshIfNeeded()
        }
        lock.lock()
        pump = timer
        lock.unlock()
        timer.resume()
    }

    /// True when a live agent process carries this surface's binding token.
    ///
    /// NEVER scans on the calling thread. `LifecycleManager.poll()` runs on the
    /// main thread at 10Hz, and a full process-table walk (proc_listallpids plus
    /// a KERN_PROCARGS2 sysctl per candidate) is far too expensive to sit in
    /// that path — doing so stalled the UI for seconds at a time. This is a pure
    /// read of the last completed scan; refreshes happen on a utility queue.
    /// upstream: PR#6798 — "no file I/O and no parsing on the main actor".
    func isAgentLive(surfaceID: UUID) -> Bool {
        scheduleRefreshIfNeeded()
        let key = surfaceID.uuidString.uppercased()
        lock.lock()
        defer { lock.unlock() }
        return liveSurfaceIDs.contains(key)
    }

    /// Force the next `isAgentLive` call to rescan. Used on lifecycle edges where
    /// staleness would be user-visible.
    func invalidate() {
        lock.lock()
        lastScan = .distantPast
        lock.unlock()
    }

    // MARK: - Scan

    /// Kicks a scan onto a background queue at most once per `rescanInterval`,
    /// and at most one at a time. Returns immediately — callers always read the
    /// previous result. Presence changes on human timescales, so being one
    /// interval stale is harmless; blocking the UI is not.
    private func scheduleRefreshIfNeeded() {
        lock.lock()
        let due = Date().timeIntervalSince(lastScan) >= rescanInterval && !scanInFlight
        if due {
            lastScan = Date()
            scanInFlight = true
        }
        lock.unlock()
        guard due else { return }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            self.scan()
            self.lock.lock()
            self.scanInFlight = false
            self.lock.unlock()
        }
    }

    private func scan() {
        let rows = FadiProcessTable.snapshot()
        let now = Date()

        var alivePIDs = Set<Int32>()
        var found = Set<String>()
        var observed: [ObservedAgentSession] = []

        for row in rows {
            alivePIDs.insert(row.pid)

            let basename = (row.name as NSString).lastPathComponent.lowercased()
            let isCandidate = agentBasenames.contains(basename) || scriptHosts.contains(basename)
            guard isCandidate else { continue }

            // Cache hit (same pid AND same start time — PID reuse invalidates).
            lock.lock()
            let cached = scopeCache[row.pid]
            lock.unlock()

            if let cached, cached.startTimeKey == row.startTimeKey {
                let expired = !cached.isAgent && now.timeIntervalSince(cached.probedAt) > negativeTTL
                if !expired {
                    if cached.isAgent, let sid = cached.surfaceID { found.insert(sid) }
                    if let row = cached.observed { observed.append(row.resampled(at: now)) }
                    continue
                }
            }

            // Probe: one sysctl gives both argv and env.
            var surfaceID: String? = nil
            var isAgent = false
            var observation: ObservedAgentSession? = nil
            if let info = FadiProcArgs.read(pid: row.pid) {
                isAgent = classify(basename: basename, argv: info.argv)
                if isAgent {
                    surfaceID = (info.environment["CMUX_SURFACE_ID"]
                                 ?? info.environment["CMUX_PANEL_ID"])?.uppercased()
                    if let surfaceID {
                        // Identity from the agent's OWN argv, the way upstream
                        // resolves an untracked claude: `--session-id <uuid>`
                        // or `--resume <uuid>`. Absent either, the registry
                        // mints a pending id that the first hook retires.
                        // upstream: PR#6798 — observe-floor identity resolution
                        observation = ObservedAgentSession(
                            sessionID: Self.sessionID(fromArgv: info.argv),
                            agentKind: AgentKind(source: "claude"),
                            surfaceID: surfaceID,
                            workspaceID: (info.environment["CMUX_WORKSPACE_ID"]
                                          ?? info.environment["CMUX_TAB_ID"])?.uppercased(),
                            pid: Int(row.pid),
                            workingDirectory: info.environment["PWD"],
                            transcriptPath: nil,
                            sampledAt: now
                        )
                    }
                }
            }

            lock.lock()
            scopeCache[row.pid] = ScopeEntry(surfaceID: surfaceID,
                                             isAgent: isAgent,
                                             startTimeKey: row.startTimeKey,
                                             probedAt: now,
                                             observed: observation)
            lock.unlock()

            if isAgent, let surfaceID { found.insert(surfaceID) }
            if let observation { observed.append(observation) }
        }

        lock.lock()
        // Drop cache entries for dead PIDs so the map can't grow without bound.
        scopeCache = scopeCache.filter { alivePIDs.contains($0.key) }
        liveSurfaceIDs = found
        lastObserved = observed
        let sink = onObservedSessions
        lock.unlock()

        sink?(observed)
    }

    /// The observe-floor snapshot from the last completed scan.
    /// upstream: PR#6798
    func observedSessions() -> [ObservedAgentSession] {
        lock.lock()
        defer { lock.unlock() }
        return lastObserved
    }

    /// Tree-aware liveness probe: is ANY agent process still alive under this
    /// surface? Used by the exit watcher, which must not end a session when the
    /// pid that died was a launcher or shim (`node`, a subrouter) rather than
    /// the agent itself.
    ///
    /// Scans directly rather than reading the cached snapshot: this is called
    /// exactly once per process death, already off the main actor, and a stale
    /// answer here would end a live session.
    /// upstream: PR#6798 — AgentChatSessionRegistry+LiveAgentPID.liveAgentPID
    ///
    /// - Parameter surfaceKey: Uppercased surface UUID string.
    /// - Returns: A live agent pid bound to the surface, or nil.
    func liveAgentPID(surfaceKey: String) -> Int? {
        let key = surfaceKey.uppercased()
        for row in FadiProcessTable.snapshot() {
            let basename = (row.name as NSString).lastPathComponent.lowercased()
            guard agentBasenames.contains(basename) || scriptHosts.contains(basename) else { continue }
            guard let info = FadiProcArgs.read(pid: row.pid),
                  classify(basename: basename, argv: info.argv) else { continue }
            let bound = (info.environment["CMUX_SURFACE_ID"]
                         ?? info.environment["CMUX_PANEL_ID"])?.uppercased()
            if bound == key { return Int(row.pid) }
        }
        return nil
    }

    /// Pulls a session id out of an agent's own argv.
    /// upstream: PR#6798 — "claude via `--session-id`/`--resume` argv"
    static func sessionID(fromArgv argv: [String]) -> String? {
        var index = 0
        while index < argv.count {
            let arg = argv[index]
            if arg == "--session-id" || arg == "--resume" || arg == "-r" {
                let next = index + 1
                if next < argv.count, !argv[next].hasPrefix("-"),
                   UUID(uuidString: argv[next]) != nil {
                    return argv[next].lowercased()
                }
            } else if let eq = arg.range(of: "="),
                      ["--session-id", "--resume"].contains(String(arg[arg.startIndex..<eq.lowerBound])) {
                let value = String(arg[eq.upperBound...])
                if UUID(uuidString: value) != nil { return value.lowercased() }
            }
            index += 1
        }
        return nil
    }

    /// Basename first; argv needles only for known script hosts.
    /// upstream: PR#6798 — deliberately ordered so shims don't false-positive.
    private func classify(basename: String, argv: [String]) -> Bool {
        if agentBasenames.contains(basename) { return true }
        guard scriptHosts.contains(basename) else { return false }
        for arg in argv {
            let lowered = arg.lowercased()
            for needle in agentArgvNeedles where lowered.contains(needle) {
                return true
            }
        }
        return false
    }
}
