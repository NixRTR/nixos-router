#!/usr/bin/env bash

# Script to download dnclient and get its SHA256 hash for Nix

set -euo pipefail

VERSION="${1:-0.8.4}"
URL="https://dl.defined.net/290ff4b6/v${VERSION}/linux/amd64/dnclient"

echo "Downloading dnclient v${VERSION}..."
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

curl -fsSL "$URL" -o "$TEMP_FILE"

echo ""
echo "SHA256 hash:"
sha256sum "$TEMP_FILE" | awk '{print $1}'

echo ""
echo "Nix hash (use this in dnclient.nix):"
nix hash file "$TEMP_FILE"

echo ""
echo "File size: $(wc -c < "$TEMP_FILE") bytes"

