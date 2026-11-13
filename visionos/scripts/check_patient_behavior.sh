#!/bin/bash
# Compiles the patient behaviour state machine for macOS and runs scripts/BehaviorCheck.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
swiftc -swift-version 5 -o "$OUT/check" MedSimXR/Models/PatientBehavior.swift scripts/BehaviorCheck/main.swift
"$OUT/check"
