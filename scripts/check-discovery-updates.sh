#!/bin/bash
# Pass the products directory from a build with ENABLE_TESTABILITY=YES.
set -euo pipefail
cd "$(dirname "$0")/.."
products=$(cd "${1:?Usage: $0 /path/to/Build/Products/Release}" && pwd)
mkdir -p "$HOME/tmp"
scratch=$(mktemp -d "$HOME/tmp/neardrop-discovery-check.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
swiftc -module-cache-path "$scratch/modules" -I "$products" -L "$products" \
  -lNearbyShare Tests/DiscoveryUpdates.swift -o "$scratch/check-discovery"
DYLD_LIBRARY_PATH="$products${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" "$scratch/check-discovery"
