#!/bin/bash
# Compiles the offline engine for macOS and runs scripts/OfflineEngineCheck against the sample scenario.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(cd .. && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
swiftc -swift-version 5 -o "$OUT/check" \
  MedSimXR/Models/Contracts.swift MedSimXR/Networking/OfflineClinicalEngine.swift \
  scripts/OfflineEngineCheck/main.swift
"$OUT/check" "$ROOT"
