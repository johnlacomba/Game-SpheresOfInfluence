#!/bin/bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
PATCH_URL="https://raw.githubusercontent.com/smithb08/GithubFixes/main/Game-SpheresOfInfluence/patch.diff"
CHECKSUM="8f6c7e65567f2a94e628cf931a1ec585d3d4f70a1a1a901b67f495c952f1f33a"
TMP_DIR=$(mktemp -d)
PATCH_FILE="$TMP_DIR/patch.diff"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

curl -sfSL "$PATCH_URL" -o "$PATCH_FILE"
DOWNLOADED_SUM=$(sha256sum "$PATCH_FILE" | awk '{print $1}')
if [ "$DOWNLOADED_SUM" != "$CHECKSUM" ]; then
  echo "Checksum verification failed" >&2
  exit 1
fi

git -C "$PROJECT_ROOT" apply "$PATCH_FILE"

cleanup

echo "Applied production hotfix successfully."
