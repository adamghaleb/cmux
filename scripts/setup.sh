#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "==> Initializing submodules..."
git submodule update --init --recursive

GHOSTTY_SHA="$(git -C ghostty rev-parse HEAD)"
CACHE_ROOT="${CMUX_GHOSTTYKIT_CACHE_DIR:-$HOME/.cache/cmux/ghosttykit}"
CACHE_DIR="$CACHE_ROOT/$GHOSTTY_SHA"
CACHE_XCFRAMEWORK="$CACHE_DIR/GhosttyKit.xcframework"
LOCAL_XCFRAMEWORK="$PROJECT_DIR/ghostty/macos/GhosttyKit.xcframework"
LOCAL_SHA_STAMP="$LOCAL_XCFRAMEWORK/.ghostty_sha"
LOCK_DIR="$CACHE_ROOT/$GHOSTTY_SHA.lock"

mkdir -p "$CACHE_ROOT"

echo "==> Ghostty submodule commit: $GHOSTTY_SHA"

LOCK_TIMEOUT=300
LOCK_START=$SECONDS
while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    if (( SECONDS - LOCK_START > LOCK_TIMEOUT )); then
        echo "==> Lock stale (>${LOCK_TIMEOUT}s), removing and retrying..."
        rmdir "$LOCK_DIR" 2>/dev/null || rm -rf "$LOCK_DIR"
        continue
    fi
    echo "==> Waiting for GhosttyKit cache lock for $GHOSTTY_SHA..."
    sleep 1
done
trap 'rmdir "$LOCK_DIR" >/dev/null 2>&1 || true' EXIT

if [ -d "$CACHE_XCFRAMEWORK" ]; then
    echo "==> Reusing cached GhosttyKit.xcframework"
else
    # Only reuse local xcframework if its SHA stamp matches the current ghostty commit.
    # Without this check, a stale build from a previous commit could be cached under
    # the wrong SHA, producing ABI mismatches.
    LOCAL_SHA=""
    if [ -f "$LOCAL_SHA_STAMP" ]; then
        LOCAL_SHA="$(cat "$LOCAL_SHA_STAMP")"
    fi

    if [ -d "$LOCAL_XCFRAMEWORK" ] && [ "$LOCAL_SHA" = "$GHOSTTY_SHA" ]; then
        echo "==> Seeding cache from existing local GhosttyKit.xcframework (SHA matches)"
    elif [ "${CMUX_FORCE_GHOSTTY_BUILD:-0}" != "1" ] && \
         "$SCRIPT_DIR/download-xcframework.sh" \
             --ghostty-dir "$PROJECT_DIR/ghostty" \
             --output-dir "$PROJECT_DIR/ghostty/macos"; then
        # Preferred path: fetch the pinned, SHA-256-verified prebuilt. No zig
        # toolchain required, and every machine gets a byte-identical artifact.
        echo "==> Downloaded pinned GhosttyKit.xcframework for $GHOSTTY_SHA"
    else
        # Fallback: build from source. Requires zig.
        if ! command -v zig &> /dev/null; then
            echo "Error: no pinned xcframework available and zig is not installed."
            echo "Install via: brew install zig   (or publish a release for $GHOSTTY_SHA — see HERMETIC.md)"
            exit 1
        fi
        echo "==> Building GhosttyKit.xcframework from source (this may take a few minutes)..."
        (
            cd ghostty
            zig build -Demit-xcframework=true -Doptimize=ReleaseFast
        )
        # Stamp the build output with the SHA it was built from
        echo "$GHOSTTY_SHA" > "$LOCAL_SHA_STAMP"
    fi

    if [ ! -d "$LOCAL_XCFRAMEWORK" ]; then
        echo "Error: GhosttyKit.xcframework not found at $LOCAL_XCFRAMEWORK"
        exit 1
    fi

    TMP_DIR="$(mktemp -d "$CACHE_ROOT/.ghosttykit-tmp.XXXXXX")"
    mkdir -p "$CACHE_DIR"
    cp -R "$LOCAL_XCFRAMEWORK" "$TMP_DIR/GhosttyKit.xcframework"
    rm -rf "$CACHE_XCFRAMEWORK"
    mv "$TMP_DIR/GhosttyKit.xcframework" "$CACHE_XCFRAMEWORK"
    rmdir "$TMP_DIR"
    echo "==> Cached GhosttyKit.xcframework at $CACHE_XCFRAMEWORK"
fi

echo "==> Creating symlink for GhosttyKit.xcframework..."
ln -sfn "$CACHE_XCFRAMEWORK" GhosttyKit.xcframework

echo "==> Setup complete!"
echo ""
echo "You can now build and run the app:"
echo "  ./scripts/reload.sh --tag first-run"
