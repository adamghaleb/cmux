// Transcribed from upstream manaflow-ai/cmux
// Packages/macOS/CmuxTerminal/Sources/CmuxTerminal/Lifecycle/TerminalChildExitPolicy.swift
// upstream: PR #8681 (state at HEAD b46dcb71c1)

/// Decides whether a child exit is a startup failure that must remain visible.
///
/// A spawn-command surface (e.g. one running `tmux -L fadi attach -t <session>`
/// per ADR-0004) has `wait-after-command` forced on by libghostty, so the app
/// owns the exit outcome: a normal exit or detach should close the pane (not
/// strand a dead surface), while an instant abnormal exit (e.g. the tmux server
/// isn't running) should keep the surface visible so the error is inspectable.
struct TerminalChildExitPolicy: Sendable {
    private let abnormalRuntimeMilliseconds: UInt64

    /// Creates a policy matching Ghostty's configured abnormal-exit threshold.
    ///
    /// - Parameter abnormalRuntimeMilliseconds: The maximum runtime Ghostty
    ///   classifies as an abnormal command exit.
    init(abnormalRuntimeMilliseconds: UInt32) {
        self.abnormalRuntimeMilliseconds = UInt64(abnormalRuntimeMilliseconds)
    }

    /// Returns whether Ghostty should retain the surface and render its error state.
    ///
    /// - Parameter runtimeMilliseconds: How long the child process survived.
    /// - Returns: `true` for startup failures; `false` for established-process exits.
    func shouldKeepSurfaceVisible(runtimeMilliseconds: UInt64) -> Bool {
        runtimeMilliseconds <= abnormalRuntimeMilliseconds
    }
}
