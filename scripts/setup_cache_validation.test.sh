#!/usr/bin/env bash
# Regression test for fadi-orchestrator #44.
#
# The bug: scripts/setup.sh decided a cache HIT with `[ -d "$CACHE_XCFRAMEWORK" ]`.
# A cache directory containing nothing but POISON.txt made setup print
# "Reusing cached... Setup complete!", exit 0, and symlink the garbage into
# the build. This test drives the real validation code that now gates that
# decision, using real static archives built on the fly (no fixtures, no
# dependency on the 540MB framework, no grep-the-source assertions).
#
# Run: ./scripts/setup_cache_validation.test.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/xcframework_validate.sh
. "$SCRIPT_DIR/lib/xcframework_validate.sh"

PASS=0
FAIL=0

ok()   { echo "  ok   - $1"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL - $1"; FAIL=$((FAIL + 1)); }

# Builds a real .a exporting the named symbol, laid out as an xcframework.
# Using a genuine archive means `nm -gU` is doing genuine work here.
make_xcframework() {
    local root="$1" symbol="$2"
    local slice="$root/macos-arm64_x86_64"
    mkdir -p "$slice"
    printf '{}\n' > "$root/Info.plist"
    printf 'void %s(void) {}\n' "$symbol" > "$root/.stub.c"
    clang -c "$root/.stub.c" -o "$root/.stub.o" 2>/dev/null
    ar rcs "$slice/libghostty.a" "$root/.stub.o" 2>/dev/null
    rm -f "$root/.stub.c" "$root/.stub.o"
}

assert_valid() {
    local dir="$1" desc="$2" reason
    if reason="$(validate_xcframework "$dir")"; then
        ok "$desc"
    else
        bad "$desc (unexpectedly rejected: $reason)"
    fi
}

assert_invalid() {
    local dir="$1" desc="$2" reason
    if reason="$(validate_xcframework "$dir")"; then
        bad "$desc (WAS ACCEPTED — this is the #44 bug)"
    else
        [ -n "$reason" ] && ok "$desc -> rejected: $reason" || bad "$desc rejected but gave no reason"
    fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== validate_xcframework =="

# The exact repro from #44: a cache directory containing only POISON.txt.
POISON="$TMP/poison/GhosttyKit.xcframework"
mkdir -p "$POISON"
echo "this is not a framework" > "$POISON/POISON.txt"
assert_invalid "$POISON" "cache dir containing only POISON.txt"

# The subtler, more dangerous case: a complete, well-formed framework built
# from a source tree without the Fadicode accent-color patch. Structurally
# perfect; silently wrong. This is what was actually sitting in Adam's cache.
WRONGSRC="$TMP/wrongsrc/GhosttyKit.xcframework"
make_xcframework "$WRONGSRC" "ghostty_surface_set_title"
assert_invalid "$WRONGSRC" "well-formed framework missing the accent-color symbol"

# Structural failures.
assert_invalid "$TMP/does-not-exist/GhosttyKit.xcframework" "nonexistent directory"

NOPLIST="$TMP/noplist/GhosttyKit.xcframework"
make_xcframework "$NOPLIST" "ghostty_surface_set_accent_color"
rm -f "$NOPLIST/Info.plist"
assert_invalid "$NOPLIST" "framework with no Info.plist"

NOLIB="$TMP/nolib/GhosttyKit.xcframework"
make_xcframework "$NOLIB" "ghostty_surface_set_accent_color"
rm -f "$NOLIB/macos-arm64_x86_64/libghostty.a"
assert_invalid "$NOLIB" "framework with no libghostty.a"

EMPTYLIB="$TMP/emptylib/GhosttyKit.xcframework"
make_xcframework "$EMPTYLIB" "ghostty_surface_set_accent_color"
: > "$EMPTYLIB/macos-arm64_x86_64/libghostty.a"
assert_invalid "$EMPTYLIB" "framework with a zero-byte libghostty.a"

# Guard against a substring match passing for the real symbol.
NEARMISS="$TMP/nearmiss/GhosttyKit.xcframework"
make_xcframework "$NEARMISS" "ghostty_surface_set_accent_color_ext"
assert_invalid "$NEARMISS" "framework exporting only a longer look-alike symbol"

# And the positive case must still pass, or the check is worthless.
GOOD="$TMP/good/GhosttyKit.xcframework"
make_xcframework "$GOOD" "ghostty_surface_set_accent_color"
assert_valid "$GOOD" "framework exporting the accent-color symbol"

# Regression: a real libghostty.a is ~285MB with a symbol table far bigger than
# the 64KB pipe buffer. An implementation that pipes `nm | grep -q` gets the
# reader exiting early, nm killed by SIGPIPE, and — because setup.sh runs under
# `set -o pipefail` — a VALID framework rejected. Tiny fixtures hide this, so
# build one with a symbol table large enough to actually fill the pipe. nm sorts
# symbols alphabetically, so the padding is named to sort AFTER the required
# symbol: an early-exit reader then matches almost immediately and abandons the
# pipe while nm still has hundreds of KB to write. That is what raises SIGPIPE.
BIG="$TMP/big/GhosttyKit.xcframework"
BIGSLICE="$BIG/macos-arm64_x86_64"
mkdir -p "$BIGSLICE"
printf '{}\n' > "$BIG/Info.plist"
{
    printf 'void ghostty_surface_set_accent_color(void) {}\n'
    for i in $(seq 1 8000); do printf 'void ghostty_zzpad_symbol_%05d(void) {}\n' "$i"; done
} > "$TMP/big.c"
clang -c "$TMP/big.c" -o "$TMP/big.o" 2>/dev/null
ar rcs "$BIGSLICE/libghostty.a" "$TMP/big.o" 2>/dev/null
echo "  (big fixture symbol table: $(nm -gU "$BIGSLICE/libghostty.a" 2>/dev/null | wc -c | tr -d ' ') bytes)"
# (this file runs under `set -uo pipefail`, so pipefail is already in force here)
assert_valid "$BIG" "large framework validated under set -o pipefail"

echo
echo "== passed: $PASS  failed: $FAIL =="
[ "$FAIL" -eq 0 ]
