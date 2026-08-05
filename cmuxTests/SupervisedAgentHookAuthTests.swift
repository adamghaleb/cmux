import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#elseif canImport(fadicode_DEV)
@testable import fadicode_DEV
#endif

/// orchestrator #67 — the capability that lets a daemon-supervised pane drive
/// Gate 2.
///
/// The socket's `cmuxOnly` boundary is unchanged. What these prove is the
/// narrow allowance around it: `agent_hook` from a same-uid non-descendant is
/// accepted only while it quotes a token this app minted for the surface the
/// payload names — the same shape #62 established for `agent_bind`, and no
/// wider.
final class SupervisedAgentHookAuthTests: XCTestCase {

    private let surface = "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
    private let daemonSession = "11111111-2222-3333-4444-555555555555"

    private var alias: String {
        FadiDaemonAttach.surfaceAlias(daemonSessionID: daemonSession)
    }

    override func tearDown() {
        FadiDaemonAttach.revokeToken(forSurface: surface)
        super.tearDown()
    }

    private func hookLine(surfaceID: String, token: String?) -> String {
        var fields = [
            "\"session_id\":\"s-1\"",
            "\"hook_event_name\":\"UserPromptSubmit\"",
            "\"surface_id\":\"\(surfaceID)\"",
            "\"_ppid\":4242"
        ]
        if let token { fields.append("\"app_token\":\"\(token)\"") }
        return "agent_hook {" + fields.joined(separator: ",") + "}"
    }

    // MARK: - The allowance

    func testHookIsAcceptedUnderTheSurfaceAlias() {
        let token = FadiDaemonAttach.mintToken(forSurface: surface, aliases: [alias])
        // The pane can only ever name the alias: it has no idea what UUID this
        // app gave the surface that attached to it.
        XCTAssertTrue(TerminalController.isTokenedAgentHook(hookLine(surfaceID: alias, token: token)))
        // And the real surface key still works, so one capability covers both
        // names of the same surface.
        XCTAssertTrue(TerminalController.isTokenedAgentHook(hookLine(surfaceID: surface, token: token)))
    }

    func testHookWithoutAValidTokenIsRefused() {
        _ = FadiDaemonAttach.mintToken(forSurface: surface, aliases: [alias])
        XCTAssertFalse(TerminalController.isTokenedAgentHook(hookLine(surfaceID: alias, token: nil)))
        XCTAssertFalse(TerminalController.isTokenedAgentHook(hookLine(surfaceID: alias, token: "guessed")))
    }

    func testATokenIsBoundToItsOwnSurface() {
        let token = FadiDaemonAttach.mintToken(forSurface: surface, aliases: [alias])
        let otherSurface = "99999999-8888-4777-8666-555555555555"
        let otherAlias = FadiDaemonAttach.surfaceAlias(daemonSessionID: "deadbeef-0000-0000-0000-000000000000")
        XCTAssertFalse(TerminalController.isTokenedAgentHook(hookLine(surfaceID: otherSurface, token: token)))
        XCTAssertFalse(TerminalController.isTokenedAgentHook(hookLine(surfaceID: otherAlias, token: token)))
    }

    func testTheAllowanceIsOneVerbOnly() {
        let token = FadiDaemonAttach.mintToken(forSurface: surface, aliases: [alias])
        let payload = "{\"surface_id\":\"\(alias)\",\"app_token\":\"\(token)\"}"
        // Holding the capability does not make the peer a descendant: nothing
        // else on the socket opens up.
        for verb in ["list_windows", "surface.create", "set_status", "quit", "agent_hookx"] {
            XCTAssertFalse(
                TerminalController.isTokenedAgentHook("\(verb) \(payload)"),
                "\(verb) must not ride in on an agent_hook capability")
            XCTAssertFalse(
                TerminalController.isTokenedAgentBind("\(verb) \(payload)"),
                "\(verb) must not ride in on an agent_bind capability")
        }
        // A bare verb with no payload is not a capability either.
        XCTAssertFalse(TerminalController.isTokenedAgentHook("agent_hook"))
        XCTAssertFalse(TerminalController.isTokenedAgentHook("agent_hook not-json"))
    }

    func testAgentBindStillWorksUnchanged() {
        let token = FadiDaemonAttach.mintToken(forSurface: surface, aliases: [alias])
        let line = "agent_bind {\"surface_id\":\"\(surface)\",\"app_token\":\"\(token)\"}"
        XCTAssertTrue(TerminalController.isTokenedAgentBind(line))
        XCTAssertFalse(TerminalController.isTokenedAgentBind(
            "agent_bind {\"surface_id\":\"\(surface)\",\"app_token\":\"nope\"}"))
    }

    // MARK: - Revocation

    func testRevokingASurfaceRevokesItsAlias() {
        let token = FadiDaemonAttach.mintToken(forSurface: surface, aliases: [alias])
        XCTAssertTrue(TerminalController.isTokenedAgentHook(hookLine(surfaceID: alias, token: token)))

        FadiDaemonAttach.revokeToken(forSurface: surface)

        // An alias that outlived its surface would be exactly the ambient
        // authority this design exists to avoid.
        XCTAssertFalse(TerminalController.isTokenedAgentHook(hookLine(surfaceID: alias, token: token)))
        XCTAssertFalse(TerminalController.isTokenedAgentHook(hookLine(surfaceID: surface, token: token)))
    }

    func testReMintingInvalidatesThePreviousToken() {
        let first = FadiDaemonAttach.mintToken(forSurface: surface, aliases: [alias])
        let second = FadiDaemonAttach.mintToken(forSurface: surface, aliases: [alias])
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(TerminalController.isTokenedAgentHook(hookLine(surfaceID: alias, token: first)))
        XCTAssertTrue(TerminalController.isTokenedAgentHook(hookLine(surfaceID: alias, token: second)))
    }

    // MARK: - Alias shape

    func testAliasMatchesWhatTheDaemonInjects() {
        // fadid's session.SurfaceAliasSuffix. If these ever diverge, every
        // supervised hook is dropped for having no binding — loudly, but
        // universally, so it is worth pinning.
        XCTAssertEqual(FadiDaemonAttach.surfaceAlias(daemonSessionID: daemonSession),
                       "\(daemonSession)-0")
    }

    // MARK: - Ingest still refuses an unbound event

    func testIngestStillDropsAnUnboundEventLoudly() {
        let response = AgentHookIngest.handle(
            payload: "{\"session_id\":\"s-1\",\"hook_event_name\":\"Stop\"}")
        XCTAssertTrue(response.hasPrefix("ERROR:"), response)
        XCTAssertTrue(response.contains("no surface binding"), response)
    }

    func testIngestIgnoresTheCapabilityFieldItselfCarries() {
        // fadid stamps `app_token` onto the payload; the event decoder must
        // simply not care about it.
        let response = AgentHookIngest.handle(
            payload: "{\"session_id\":\"s-1\",\"hook_event_name\":\"Stop\","
                + "\"surface_id\":\"\(alias)\",\"app_token\":\"whatever\",\"_ppid\":7}")
        XCTAssertTrue(response.hasPrefix("OK:"), response)
    }
}
