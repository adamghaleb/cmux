import Foundation
import Darwin
#if DEBUG
import Bonsplit
#endif

// orchestrator #62 — the app's half of the binding handshake.
//
// When a surface is created to attach to a daemon-owned tmux session, the app
// holds exactly one fact nobody else can derive: WHICH surface it is. It
// reports that to `fadid`, and `fadid` answers by asserting the binding back
// over this app's control socket (`agent_bind`). Nothing here inspects the
// agent, guesses a pid, or reads a title — it only says "surface X is now
// pointed at session Y, and here is where to reach me".
//
// Deliberately narrow: it fires only on a spawn command that is unambiguously
// a fadi tmux attach. Anything else is left alone.
enum FadiDaemonAttach {

    // MARK: - Capability tokens

    /// Surface key -> the token handed to fadid for that surface.
    ///
    /// `fadid` cannot pass the socket's descendant check: it runs under the
    /// user's own launchd and it owned the agent before this app existed. The
    /// alternative to widening the socket for every same-uid process is to
    /// hand it a secret. The app mints one per attach report, sends it over
    /// fadid's own 0700/0600 socket, and accepts `agent_bind` back only from
    /// whoever can quote it — one verb, one surface, no ambient authority.
    ///
    /// orchestrator #67 adds a second key for the same token: the surface
    /// ALIAS (`<daemon-session-id>-0`). A hook event from a supervised pane is
    /// named by the alias — the pane cannot know this app's surface UUID, and
    /// the registry re-keys aliases onto real surfaces already (#62). Keying
    /// the capability the same way lets `agent_hook` be authorized without a
    /// main-actor registry lookup on the socket thread, and without widening
    /// what the token grants: it still names one surface.
    private static let tokenLock = NSLock()
    private static var tokensBySurface: [String: String] = [:]

    /// The `CMUX_SURFACE_ID` fadid injects into a supervised pane. Mirrors
    /// `session.SurfaceAliasSuffix` on the daemon side.
    static func surfaceAlias(daemonSessionID: String) -> String {
        daemonSessionID + "-0"
    }

    /// Mints (or re-mints) the token for a surface and returns it.
    ///
    /// - Parameters:
    ///   - surfaceKey: This app's surface UUID.
    ///   - aliases: Extra keys the same capability answers to — the supervised
    ///     pane's binding token. Never a wildcard; each one names this surface.
    static func mintToken(forSurface surfaceKey: String, aliases: [String] = []) -> String {
        let token = UUID().uuidString + "-" + UUID().uuidString
        tokenLock.lock()
        tokensBySurface[surfaceKey.uppercased()] = token
        for alias in aliases where !alias.isEmpty {
            tokensBySurface[alias.uppercased()] = token
        }
        tokenLock.unlock()
        return token
    }

    /// Constant-time-ish check that a token was minted for this surface.
    static func tokenIsValid(_ token: String, forSurface surfaceID: String) -> Bool {
        tokenLock.lock()
        let expected = tokensBySurface[surfaceID.uppercased()]
        tokenLock.unlock()
        guard let expected, expected.count == token.count else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(expected.utf8, token.utf8) { difference |= a ^ b }
        return difference == 0
    }

    /// Forgets a surface's token (surface closed), including every alias that
    /// answered to the same capability. An alias that outlived its surface
    /// would be exactly the ambient authority this design exists to avoid.
    static func revokeToken(forSurface surfaceKey: String) {
        tokenLock.lock()
        if let token = tokensBySurface.removeValue(forKey: surfaceKey.uppercased()) {
            for (key, value) in tokensBySurface where value == token {
                tokensBySurface.removeValue(forKey: key)
            }
        }
        tokenLock.unlock()
    }

    /// Matches `tmux … -L fadi … attach … -t [fadi/]<uuid>` in any argument
    /// order, which is how ADR-0004 has the app render a supervised session.
    private static let sessionPattern = try? NSRegularExpression(
        pattern: #"-t\s+(?:=)?(?:fadi/)?([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})"#
    )

    /// The fadid session id a spawn command attaches to, or nil.
    ///
    /// - Parameter command: The surface's spawn command, as given to
    ///   `surface.create`.
    static func daemonSessionID(spawnCommand command: String?) -> String? {
        guard let command, !command.isEmpty else { return nil }
        let lowered = command.lowercased()
        guard lowered.contains("tmux"), lowered.contains("attach") else { return nil }
        // The socket name is what makes it OURS. A plain `tmux attach` on the
        // user's default server is not a daemon session and must not be
        // reported as one.
        guard lowered.contains("-l fadi") || lowered.contains("-lfadi")
                || lowered.contains("-l=fadi") else { return nil }

        let range = NSRange(command.startIndex..., in: command)
        guard let match = sessionPattern?.firstMatch(in: command, range: range),
              match.numberOfRanges > 1,
              let idRange = Range(match.range(at: 1), in: command) else { return nil }
        return String(command[idRange]).lowercased()
    }

    /// Reports an attach to fadid, off the calling thread. Fire and forget:
    /// the binding arrives back over the socket as `agent_bind`, so there is
    /// nothing to await here.
    ///
    /// - Parameters:
    ///   - surfaceID: This app's surface UUID.
    ///   - command: The surface's spawn command.
    ///   - appSocketPath: This app's own control socket, so the daemon knows
    ///     where to assert. A tagged dev build has its own socket, which is
    ///     exactly why this is reported rather than assumed.
    static func reportIfDaemonSession(
        surfaceID: UUID,
        spawnCommand command: String?,
        appSocketPath: String
    ) {
        guard let sessionID = daemonSessionID(spawnCommand: command),
              !appSocketPath.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            report(sessionID: sessionID, surfaceID: surfaceID, appSocketPath: appSocketPath)
        }
    }

    // MARK: - Transport

    /// fadid's UDS API socket.
    static var daemonSocketPath: String {
        if let override = ProcessInfo.processInfo.environment["FADID_SOCKET"], !override.isEmpty {
            return override
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/fadid/fadid.sock"
    }

    private static func report(sessionID: String, surfaceID: UUID, appSocketPath: String) {
        let body: [String: String] = [
            "surface_id": surfaceID.uuidString.uppercased(),
            "app_socket": appSocketPath,
            // One capability, two names: the surface this app knows, and the
            // alias its supervised pane carries. #62 + #67.
            "app_token": mintToken(
                forSurface: surfaceID.uuidString,
                aliases: [surfaceAlias(daemonSessionID: sessionID)]
            )
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: body) else { return }

        // Three tries, 1s -> 2s -> 4s with jitter. The daemon is under launchd
        // and re-adopts on restart, so a miss here is usually a restart window,
        // not a permanent failure. Never retry a 4xx: a rejected binding is
        // wrong, and repeating it cannot make it right.
        var delay: TimeInterval = 1.0
        for attempt in 0..<3 {
            if attempt > 0 {
                Thread.sleep(forTimeInterval: delay + Double.random(in: 0...(delay / 2)))
                delay *= 2
            }
            switch post(path: "/sessions/\(sessionID)/attach", body: json) {
            case .success(let status):
                #if DEBUG
                dlog("fadid.attach session=\(sessionID) surface=\(surfaceID.uuidString) status=\(status)")
                #endif
                if status < 500 { return }
            case .failure:
                continue
            }
        }
        #if DEBUG
        dlog("fadid.attach FAILED session=\(sessionID) surface=\(surfaceID.uuidString)")
        #endif
    }

    /// Minimal HTTP/1.1 POST over a unix socket. `URLSession` cannot speak to
    /// a UDS, and fadid's API is a handful of JSON routes, so a hand-rolled
    /// request is smaller than any dependency that would hide it.
    private static func post(path: String, body: Data) -> Result<Int, Error> {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .failure(POSIXError(.ECONNREFUSED)) }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let socketPath = daemonSocketPath
        let pathBytes = Array(socketPath.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            return .failure(POSIXError(.ENAMETOOLONG))
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            guard let base = raw.baseAddress else { return }
            base.copyMemory(from: pathBytes, byteCount: pathBytes.count)
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let connected = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return .failure(POSIXError(.ECONNREFUSED)) }

        var request = Data()
        let head = "POST \(path) HTTP/1.1\r\nHost: fadid\r\nContent-Type: application/json\r\n"
            + "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        request.append(head.data(using: .utf8) ?? Data())
        request.append(body)

        let written: Int = request.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return -1 }
            return Darwin.write(fd, base, raw.count)
        }
        guard written == request.count else { return .failure(POSIXError(.EIO)) }

        var buffer = [UInt8](repeating: 0, count: 4096)
        let readCount = Darwin.read(fd, &buffer, buffer.count)
        guard readCount > 0 else { return .failure(POSIXError(.EIO)) }
        let response = String(decoding: buffer[0..<readCount], as: UTF8.self)
        // "HTTP/1.1 200 OK"
        let fields = response.split(separator: " ", maxSplits: 2)
        guard fields.count > 1, let status = Int(fields[1]) else {
            return .failure(POSIXError(.EBADMSG))
        }
        return .success(status)
    }
}
