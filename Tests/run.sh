#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Airfryer Mac contributors. See the LICENSE file.
# Compiles the logic and tests it against the fake Home Assistant (no real device involved).
set -euo pipefail
cd "$(dirname "$0")/.."
PORT=18123
python3 -I Tests/mock_ha.py $PORT & MOCK=$!
trap 'kill $MOCK 2>/dev/null' EXIT
mkdir -p build
swiftc -swift-version 5 -O Sources/Core.swift Tests/main.swift -o build/tests
sleep 1
MOCK_PORT=$PORT build/tests
