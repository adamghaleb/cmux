#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# shellcheck source=lib/xcframework_validate.sh
. "$SCRIPT_DIR/lib/xcframework_validate.sh"

echo "==> Initializing submodules..."
git submodule update --init --recursive

# NOTE: the zig check used to live here, unconditionally. That made a fresh
# clone unbuildable without zig even when a perfectly valid cached
# GhosttyKit.xcframework was already on disk. zig is only needed on the path
# that actually compiles ghostty, so the check moved down to that path.

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

# A cache HIT must be justified by content, not by the key existing. See
# scripts/lib/xcframework_validate.sh for why (fadi-orchestrator #44).
CACHE_HIT=0
if [ -e "$CACHE_XCFRAMEWORK" ]; then
    if CACHE_REJECT_REASON="$(validate_xcframework "$CACHE_XCFRAMEWORK")"; then
        echo "==> Reusing cached GhosttyKit.xcframework (content verified)"
        CACHE_HIT=1
    else
        echo "==> WARNING: cached GhosttyKit.xcframework failed content validation."
        echo "==>          path:   $CACHE_XCFRAMEWORK"
        echo "==>          reason: $CACHE_REJECT_REASON"
        echo "==> Treating as a cache MISS and rebuilding (the bad entry will be replaced)."
    fi
fi

if [ "$CACHE_HIT" -eq 0 ]; then
    # Only reuse local xcframework if its SHA stamp matches the current ghostty commit.
    # Without this check, a stale build from a previous commit could be cached under
    # the wrong SHA, producing ABI mismatches.
    LOCAL_SHA=""
    if [ -f "$LOCAL_SHA_STAMP" ]; then
        LOCAL_SHA="$(cat "$LOCAL_SHA_STAMP")"
    fi

    SEEDED=0
    if [ "$LOCAL_SHA" = "$GHOSTTY_SHA" ] && LOCAL_REJECT_REASON="$(validate_xcframework "$LOCAL_XCFRAMEWORK")"; then
        echo "==> Seeding cache from existing local GhosttyKit.xcframework (SHA matches, content verified)"
        SEEDED=1
    elif [ "$LOCAL_SHA" = "$GHOSTTY_SHA" ]; then
        # The stamp claims this is the right commit but the content disagrees.
        # Never seed the cache from it — that is exactly how a poisoned entry is born.
        echo "==> WARNING: local GhosttyKit.xcframework claims SHA $GHOSTTY_SHA but failed validation."
        echo "==>          reason: $LOCAL_REJECT_REASON"
        echo "==> Rebuilding from source instead of seeding the cache from it."
    fi

    if [ "$SEEDED" -eq 0 ]; then
        echo "==> Checking for zig (required to build GhosttyKit)..."
        if ! command -v zig &> /dev/null; then
            echo "Error: zig is not installed, and no valid prebuilt GhosttyKit.xcframework"
            echo "       was found for ghostty $GHOSTTY_SHA."
            echo "Install via: brew install zig"
            exit 1
        fi

        echo "==> Building GhosttyKit.xcframework (this may take a few minutes)..."
        (
            cd ghostty
            zig build -Demit-xcframework=true -Doptimize=ReleaseFast
        )
        # Stamp the build output with the SHA it was built from
        echo "$GHOSTTY_SHA" > "$LOCAL_SHA_STAMP"
    fi

    # Whatever produced it — build or seed — it must pass before it is allowed
    # into the cache. A bad artifact caught here costs one rebuild; a bad
    # artifact cached here poisons every future clone that hits this key.
    if ! BUILD_REJECT_REASON="$(validate_xcframework "$LOCAL_XCFRAMEWORK")"; then
        echo "Error: GhosttyKit.xcframework at $LOCAL_XCFRAMEWORK is not usable."
        echo "       reason: $BUILD_REJECT_REASON"
        echo "       Refusing to cache it. Check the ghostty submodule source tree."
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

# Final guard: whatever the symlink now resolves to is what Xcode will link.
if ! FINAL_REJECT_REASON="$(validate_xcframework "$PROJECT_DIR/GhosttyKit.xcframework")"; then
    echo "Error: GhosttyKit.xcframework symlink does not resolve to a valid framework."
    echo "       reason: $FINAL_REJECT_REASON"
    exit 1
fi

echo "==> Setup complete!"
echo ""
echo "You can now build and run the app:"
echo "  ./scripts/reload.sh --tag first-run"
