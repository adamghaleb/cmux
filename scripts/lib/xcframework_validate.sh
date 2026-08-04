#!/usr/bin/env bash
# Content validation for a GhosttyKit.xcframework directory.
#
# Why this exists (fadi-orchestrator #44): setup.sh used to accept a cache entry
# on a bare `[ -d "$CACHE_XCFRAMEWORK" ]` test. Any directory passed — including
# one containing nothing but a POISON.txt file, and including a framework built
# from a source tree that lacks the Fadicode accent-color patch. Both cases
# printed "Reusing cached... Setup complete!", exited 0, and symlinked garbage
# into the build. A cache key is not evidence about cache contents.
#
# Sourced by scripts/setup.sh and exercised directly by
# scripts/setup_cache_validation.test.sh.

# The C symbol the Fadicode layer calls. A framework built from the wrong source
# tree still has a plausible ABI and a plausible directory shape, so structural
# checks alone cannot tell it apart — only the symbol can.
GHOSTTY_REQUIRED_SYMBOL="${GHOSTTY_REQUIRED_SYMBOL:-_ghostty_surface_set_accent_color}"

# validate_xcframework <path-to-GhosttyKit.xcframework>
#
# Returns 0 when the framework is structurally complete AND its macOS static
# library exports the required symbol. Returns non-zero otherwise, printing a
# one-line human-readable reason on stdout (empty on success, so callers can do
#   if REASON="$(validate_xcframework "$dir")"; then ... else echo "$REASON"; fi
# ).
validate_xcframework() {
    local xcf="$1"
    local macos_lib="$xcf/macos-arm64_x86_64/libghostty.a"

    if [ -z "$xcf" ]; then
        echo "no path given"
        return 1
    fi
    if [ ! -d "$xcf" ]; then
        echo "not a directory: $xcf"
        return 1
    fi
    if [ ! -f "$xcf/Info.plist" ]; then
        echo "missing Info.plist (not an xcframework)"
        return 1
    fi
    if [ ! -f "$macos_lib" ]; then
        echo "missing macos-arm64_x86_64/libghostty.a"
        return 1
    fi
    if [ ! -s "$macos_lib" ]; then
        echo "macos-arm64_x86_64/libghostty.a is empty"
        return 1
    fi
    # Deliberately NOT `nm ... | grep -q ...`. Callers run under `set -o pipefail`,
    # and on a real libghostty.a (~285MB, symbol table far larger than a 64KB pipe
    # buffer) `grep -q` exits at the first match, nm dies of SIGPIPE, and pipefail
    # reports the whole pipeline as failed — rejecting a perfectly good framework.
    # Small test fixtures never trigger it because nm finishes before grep exits.
    # Process substitution keeps grep's exit status the only one that matters.
    if ! grep -q "[[:space:]]${GHOSTTY_REQUIRED_SYMBOL}\$" < <(nm -gU "$macos_lib" 2>/dev/null); then
        echo "libghostty.a does not export ${GHOSTTY_REQUIRED_SYMBOL} (built from the wrong source tree?)"
        return 1
    fi

    return 0
}
