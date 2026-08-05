import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#elseif canImport(fadicode_DEV)
// This fork ships the Debug app as `fadicode DEV`, so the module is
// `fadicode_DEV`. Kept last so upstream's own module names still win.
@testable import fadicode_DEV
#endif

/// orchestrator #62 — the daemon-asserted binding seam.
///
/// These drive the real ingest + registry paths, not their shape: a payload
/// goes in the way `fadid` writes it, and the assertions are made against what
/// a Pixel Pet or tab rail would actually read (`stateBySurfaceID`).
final class AgentBindingAssertionTests: XCTestCase {

    private func payload(
        surface: UUID,
        alias: String,
        daemonSession: String = "11111111-2222-3333-4444-555555555555",
        claudeSession: String? = nil,
        pid: Int? = 4242
    ) -> String {
        var fields: [String] = [
            "\"surface_id\":\"\(surface.uuidString)\"",
            "\"surface_alias\":\"\(alias)\"",
            "\"daemon_session_id\":\"\(daemonSession)\"",
            "\"_source\":\"fadid\""
        ]
        if let claudeSession { fields.append("\"session_id\":\"\(claudeSession)\"") }
        if let pid { fields.append("\"agent_pid\":\(pid)") }
        return "{" + fields.joined(separator: ",") + "}"
    }

    // MARK: - Ingest

    func testAssertionWithoutASurfaceUUIDIsDroppedLoudly() {
        let reply = AgentBindingIngest.handle(
            payload: "{\"surface_id\":\"not-a-uuid\",\"daemon_session_id\":\"d\"}"
        )
        XCTAssertTrue(reply.hasPrefix("ERROR"), reply)
    }

    func testAssertionWithoutADaemonSessionIsDroppedLoudly() {
        let reply = AgentBindingIngest.handle(
            payload: "{\"surface_id\":\"\(UUID().uuidString)\",\"daemon_session_id\":\"\"}"
        )
        XCTAssertTrue(reply.hasPrefix("ERROR"), reply)
    }

    func testEmptyPayloadIsDroppedLoudly() {
        XCTAssertTrue(AgentBindingIngest.handle(payload: "   ").hasPrefix("ERROR"))
    }

    func testWellFormedAssertionIsAccepted() {
        let surface = UUID()
        let reply = AgentBindingIngest.handle(
            payload: payload(surface: surface, alias: "abc-0")
        )
        XCTAssertTrue(reply.hasPrefix("OK"), reply)
        XCTAssertTrue(reply.contains("pid=4242"), reply)
    }

    // MARK: - Registry

    @MainActor
    func testAssertedBindingPublishesStateForTheSurface() {
        let registry = AgentSessionRegistry.shared
        let surface = UUID()
        let daemonID = UUID().uuidString

        XCTAssertNil(registry.state(surfaceID: surface))

        registry.assertBinding(decoded(payload(
            surface: surface, alias: daemonID + "-0", daemonSession: daemonID
        )))

        // This is the exact read the Pixel Pet and the tab rail perform. Before
        // #62 a tmux-attached surface never appeared here at all.
        XCTAssertEqual(registry.state(surfaceID: surface)?.label, "idle")
        let record = registry.record(surfaceID: surface)
        XCTAssertEqual(record?.pid, 4242, "the asserted pid is what arms the exit backstop")
        XCTAssertFalse(record?.hasHookLifecycleState ?? true,
                       "the daemon asserts identity, never activity")
    }

    @MainActor
    func testAHookCarryingTheDaemonTokenRekeysOntoTheRealSurface() {
        let registry = AgentSessionRegistry.shared
        let surface = UUID()
        let daemonID = UUID().uuidString
        let alias = daemonID + "-0"
        let claudeSession = UUID().uuidString

        registry.assertBinding(decoded(payload(
            surface: surface, alias: alias, daemonSession: daemonID
        )))

        // A hook fired inside the supervised pane carries the token fadid
        // injected — never this app's surface UUID, which did not exist when
        // the agent started. It must land on the real surface anyway.
        registry.noteHookEvent(AgentHookEvent(
            sessionID: claudeSession,
            name: .userPromptSubmit,
            source: "claude",
            surfaceID: alias
        ))
        XCTAssertEqual(registry.state(surfaceID: surface)?.label, "working")

        registry.noteHookEvent(AgentHookEvent(
            sessionID: claudeSession,
            name: .stop,
            source: "claude",
            surfaceID: alias
        ))
        XCTAssertEqual(registry.state(surfaceID: surface)?.label, "idle")
    }

    @MainActor
    func testAnUnaliasedTokenStillFindsNoSurface() {
        let registry = AgentSessionRegistry.shared
        // A token nobody asserted resolves to itself, fails to parse as a
        // surface UUID, and is therefore never published. No guessing.
        registry.noteHookEvent(AgentHookEvent(
            sessionID: UUID().uuidString,
            name: .userPromptSubmit,
            source: "claude",
            surfaceID: "99999999-8888-7777-6666-555555555555-0"
        ))
        let published = registry.stateBySurfaceID.keys.map(\.uuidString)
        XCTAssertFalse(published.contains { $0.hasPrefix("99999999") })
    }

    @MainActor
    func testTheObserveFloorRekeysThroughTheAssertedAlias() {
        let registry = AgentSessionRegistry.shared
        let surface = UUID()
        let daemonID = UUID().uuidString
        let alias = daemonID + "-0"

        registry.assertBinding(decoded(payload(
            surface: surface, alias: alias, daemonSession: daemonID, pid: 5150
        )))

        // The process-table row for a supervised agent carries the alias in its
        // environment. One live pid is one session: this must refresh the
        // asserted record, not mint a rival pending one on the same surface.
        registry.applyObservedSessions([
            ObservedAgentSession(
                sessionID: nil,
                agentKind: AgentKind(source: "claude"),
                surfaceID: alias,
                pid: 5150
            )
        ])
        let onSurface = registry.allRecords().filter { $0.surfaceID == surface.uuidString.uppercased() }
        XCTAssertEqual(onSurface.count, 1, "observe floor duplicated the asserted record")
        XCTAssertEqual(onSurface.first?.pid, 5150)
    }

    @MainActor
    func testReassertingIsIdempotent() {
        let registry = AgentSessionRegistry.shared
        let surface = UUID()
        let daemonID = UUID().uuidString
        let binding = decoded(payload(surface: surface, alias: daemonID + "-0", daemonSession: daemonID))

        registry.assertBinding(binding)
        let first = registry.record(surfaceID: surface)
        registry.assertBinding(binding)
        registry.assertBinding(binding)
        let after = registry.allRecords().filter { $0.surfaceID == surface.uuidString.uppercased() }

        XCTAssertEqual(after.count, 1, "re-assertion must not fan out records")
        XCTAssertEqual(after.first?.sessionID, first?.sessionID)
    }

    // MARK: - The app's half of the handshake

    func testDaemonSessionIDIsExtractedFromATmuxAttachSpawnCommand() {
        let id = "c93d6d0d-7aec-46a2-9ae7-73d433fa3905"
        XCTAssertEqual(
            FadiDaemonAttach.daemonSessionID(spawnCommand: "tmux -L fadi attach -t fadi/\(id)"),
            id
        )
        XCTAssertEqual(
            FadiDaemonAttach.daemonSessionID(spawnCommand: "/usr/local/bin/tmux -L fadi attach-session -t =fadi/\(id)"),
            id
        )
    }

    func testNonDaemonSpawnCommandsAreLeftAlone() {
        let id = "c93d6d0d-7aec-46a2-9ae7-73d433fa3905"
        // The user's own default tmux server is not ours to report.
        XCTAssertNil(FadiDaemonAttach.daemonSessionID(spawnCommand: "tmux attach -t \(id)"))
        XCTAssertNil(FadiDaemonAttach.daemonSessionID(spawnCommand: "tmux -L other attach -t fadi/\(id)"))
        XCTAssertNil(FadiDaemonAttach.daemonSessionID(spawnCommand: "tmux -L fadi new-session"))
        XCTAssertNil(FadiDaemonAttach.daemonSessionID(spawnCommand: nil))
        XCTAssertNil(FadiDaemonAttach.daemonSessionID(spawnCommand: ""))
        XCTAssertNil(FadiDaemonAttach.daemonSessionID(spawnCommand: "claude"))
    }

    // MARK: -

    private func decoded(_ json: String) -> AssertedAgentBinding {
        // swiftlint:disable:next force_try
        try! AssertedAgentBinding.decode(Data(json.utf8))
    }
}
