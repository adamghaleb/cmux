#!/usr/bin/env bash
# Download a pre-built GhosttyKit.xcframework from the manaflow-ai/ghostty releases.
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
#   RETRY_DELAY     Seconds between retries (default: 20)
#
# The script determines the ghostty SHA from the submodule, builds the release
# URL, and downloads with retry logic. On success, GhosttyKit.xcframework/ will
# exist in the output directory.
set -euo pipefail

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

GHOSTTY_SHA=$(git -C "$GHOSTTY_DIR" rev-parse HEAD)
TAG="xcframework-$GHOSTTY_SHA"
URL="https://github.com/manaflow-ai/ghostty/releases/download/$TAG/GhosttyKit.xcframework.tar.gz"
TARBALL="$OUTPUT_DIR/GhosttyKit.xcframework.tar.gz"

echo "Downloading xcframework for ghostty $GHOSTTY_SHA"

for i in $(seq 1 "$MAX_RETRIES"); do
  if curl -fSL -o "$TARBALL" "$URL"; then
    echo "Download succeeded on attempt $i"
    break
  fi
  if [ "$i" -eq "$MAX_RETRIES" ]; then
    echo "Failed to download xcframework after $MAX_RETRIES attempts" >&2
    exit 1
  fi
  echo "Attempt $i/$MAX_RETRIES failed, retrying in ${RETRY_DELAY}s..."
  sleep "$RETRY_DELAY"
done

tar xzf "$TARBALL" -C "$OUTPUT_DIR"
rm "$TARBALL"

if [ ! -d "$OUTPUT_DIR/GhosttyKit.xcframework" ]; then
  echo "Error: GhosttyKit.xcframework not found after extraction" >&2
  exit 1
fi

echo "GhosttyKit.xcframework ready at $OUTPUT_DIR/GhosttyKit.xcframework"
