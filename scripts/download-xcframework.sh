#!/usr/bin/env bash
# Download the pinned pre-built GhosttyKit.xcframework from the
# adamghaleb/ghostty releases and verify its SHA-256 before extracting.
#
# Usage:
#   ./scripts/download-xcframework.sh [--ghostty-dir <path>] [--output-dir <path>]
#
# Options:
#   --ghostty-dir   Path to the ghostty submodule (default: ./ghostty)
#   --output-dir    Directory to extract the xcframework into (default: .)
#
# Environment:
#   MAX_RETRIES     Number of download attempts (default: 30)
#   RETRY_DELAY     Initial seconds between retries (default: 20, capped backoff)
#   GHOSTTY_REPO    Release repo (default: adamghaleb/ghostty)
#
# The release tag is derived from the ghostty submodule SHA, so the artifact
# always matches the pinned source. The expected checksum lives in
# ghostty-xcframework.sha256 next to this repo's root; a mismatch is fatal.
# See HERMETIC.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

GHOSTTY_DIR="./ghostty"
OUTPUT_DIR="."

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ghostty-dir)
      GHOSTTY_DIR="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,/^set /{ /^#/s/^# \?//p }' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

MAX_RETRIES="${MAX_RETRIES:-30}"
RETRY_DELAY="${RETRY_DELAY:-20}"
GHOSTTY_REPO="${GHOSTTY_REPO:-adamghaleb/ghostty}"
CHECKSUM_FILE="$PROJECT_DIR/ghostty-xcframework.sha256"

GHOSTTY_SHA=$(git -C "$GHOSTTY_DIR" rev-parse HEAD)
TAG="xcframework-$GHOSTTY_SHA"
URL="https://github.com/$GHOSTTY_REPO/releases/download/$TAG/GhosttyKit.xcframework.tar.gz"
TARBALL="$OUTPUT_DIR/GhosttyKit.xcframework.tar.gz"

# The pinned checksum is keyed by ghostty SHA so the file documents exactly
# which source revision each artifact corresponds to.
EXPECTED_SHA256=""
if [ -f "$CHECKSUM_FILE" ]; then
  EXPECTED_SHA256="$(awk -v sha="$GHOSTTY_SHA" '$2 == sha { print $1 }' "$CHECKSUM_FILE" | head -n1)"
fi

if [ -z "$EXPECTED_SHA256" ]; then
  echo "Error: no pinned SHA-256 for ghostty $GHOSTTY_SHA in $CHECKSUM_FILE" >&2
  echo "       Publish a release for this SHA and record its checksum. See HERMETIC.md." >&2
  exit 1
fi

echo "Downloading xcframework for ghostty $GHOSTTY_SHA from $GHOSTTY_REPO"
echo "Expecting SHA-256 $EXPECTED_SHA256"

delay="$RETRY_DELAY"
for i in $(seq 1 "$MAX_RETRIES"); do
  if curl -fSL --retry 0 -o "$TARBALL" "$URL"; then
    echo "Download succeeded on attempt $i"
    break
  fi
  if [ "$i" -eq "$MAX_RETRIES" ]; then
    echo "Failed to download xcframework after $MAX_RETRIES attempts" >&2
    exit 1
  fi
  # Exponential backoff with jitter, capped at 120s.
  jitter=$(( RANDOM % 5 ))
  echo "Attempt $i/$MAX_RETRIES failed, retrying in $((delay + jitter))s..."
  sleep "$((delay + jitter))"
  delay=$(( delay * 2 ))
  [ "$delay" -gt 120 ] && delay=120
done

ACTUAL_SHA256="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  echo "Error: SHA-256 mismatch for $TARBALL" >&2
  echo "  expected: $EXPECTED_SHA256" >&2
  echo "  actual:   $ACTUAL_SHA256" >&2
  echo "Refusing to extract an artifact that does not match the pin." >&2
  rm -f "$TARBALL"
  exit 1
fi
echo "SHA-256 verified."

rm -rf "$OUTPUT_DIR/GhosttyKit.xcframework"
tar xzf "$TARBALL" -C "$OUTPUT_DIR"
rm "$TARBALL"

if [ ! -d "$OUTPUT_DIR/GhosttyKit.xcframework" ]; then
  echo "Error: GhosttyKit.xcframework not found after extraction" >&2
  exit 1
fi

# Stamp the extracted framework so setup.sh can tell which SHA it came from.
echo "$GHOSTTY_SHA" > "$OUTPUT_DIR/GhosttyKit.xcframework/.ghostty_sha"

echo "GhosttyKit.xcframework ready at $OUTPUT_DIR/GhosttyKit.xcframework"
