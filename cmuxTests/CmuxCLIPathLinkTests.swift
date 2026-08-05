import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#elseif canImport(fadicode_DEV)
@testable import fadicode_DEV
#endif

/// orchestrator #65 — the launch-time CLI link.
///
/// Gate 2's only live input is a Claude Code hook, and a hook runs in a bare
/// environment: no PATH, no shell rc. So the app owes it a file at a fixed
/// absolute path. These tests pin the behaviours that decide whether that file
/// is trustworthy — most of them are about what the app refuses to do, since a
/// link that points at nothing fails exactly as quietly as no link at all.
final class CmuxCLIPathLinkTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cmux-cli-link-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeSource(named name: String = "cmux") throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        return url
    }

    private func destination() -> URL {
        root.appendingPathComponent("bin/cmux")
    }

    func testLinksWhenDestinationIsAbsent() throws {
        let source = try makeSource()
        let outcome = CmuxCLIPathInstaller.linkUserPath(
            sourceURL: source,
            destinationURL: destination(),
            allowTemporarySource: true
        )
        XCTAssertEqual(
            outcome,
            .linked(destination: destination().path, source: source.standardizedFileURL.path)
        )
        // The parent directory is created on the way, and the link resolves.
        let resolved = try FileManager.default.destinationOfSymbolicLink(atPath: destination().path)
        XCTAssertEqual(resolved, source.standardizedFileURL.path)
    }

    func testSecondRunIsANoOp() throws {
        let source = try makeSource()
        _ = CmuxCLIPathInstaller.linkUserPath(
            sourceURL: source, destinationURL: destination(), allowTemporarySource: true)
        let outcome = CmuxCLIPathInstaller.linkUserPath(
            sourceURL: source, destinationURL: destination(), allowTemporarySource: true)
        XCTAssertEqual(outcome, .alreadyCurrent)
    }

    func testRepointsAStaleLink() throws {
        let stale = try makeSource(named: "old-cmux")
        let fresh = try makeSource(named: "new-cmux")
        try FileManager.default.createDirectory(
            at: destination().deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: destination(), withDestinationURL: stale)

        let outcome = CmuxCLIPathInstaller.linkUserPath(
            sourceURL: fresh, destinationURL: destination(), allowTemporarySource: true)

        XCTAssertEqual(
            outcome,
            .linked(destination: destination().path, source: fresh.standardizedFileURL.path)
        )
    }

    /// A dangling link is the failure mode this whole issue is about: it looks
    /// installed and does nothing. It must be repaired, not respected.
    func testReplacesADanglingLink() throws {
        let source = try makeSource()
        let missing = root.appendingPathComponent("deleted-build/cmux")
        try FileManager.default.createDirectory(
            at: destination().deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: destination(), withDestinationURL: missing)

        let outcome = CmuxCLIPathInstaller.linkUserPath(
            sourceURL: source, destinationURL: destination(), allowTemporarySource: true)

        XCTAssertEqual(
            outcome,
            .linked(destination: destination().path, source: source.standardizedFileURL.path)
        )
    }

    /// `~/.local/bin` is the user's own directory. If a real file is sitting at
    /// our name, it is not ours to delete.
    func testRefusesToClobberARegularFile() throws {
        let source = try makeSource()
        try FileManager.default.createDirectory(
            at: destination().deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("someone else's tool".utf8).write(to: destination())

        let outcome = CmuxCLIPathInstaller.linkUserPath(
            sourceURL: source, destinationURL: destination(), allowTemporarySource: true)

        XCTAssertEqual(outcome, .refusedNonSymlink(destination: destination().path))
        XCTAssertEqual(
            try String(contentsOf: destination(), encoding: .utf8), "someone else's tool")
    }

    /// A tagged/throwaway build must not take ownership of a durable link: it
    /// gets deleted, and then the hook is silently deaf again.
    func testSkipsBuildsRunningFromATemporaryDirectory() throws {
        let source = try makeSource()
        let outcome = CmuxCLIPathInstaller.linkUserPath(
            sourceURL: source, destinationURL: destination(), allowTemporarySource: false)

        XCTAssertEqual(outcome, .skippedTemporaryBuild(source: source.standardizedFileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination().path))
    }

    func testReportsAMissingBundledCLI() {
        let outcome = CmuxCLIPathInstaller.linkUserPath(
            sourceURL: root.appendingPathComponent("nope"),
            destinationURL: destination(),
            allowTemporarySource: true
        )
        XCTAssertEqual(outcome, .noBundledCLI)
    }
}
