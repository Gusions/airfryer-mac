#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Airfryer Mac contributors. See the LICENSE file.
# Builds the app and packs dist/AirfryerMac-<version>.zip (ad-hoc signed, not notarized).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Info.plist)"
bash Tools/build.sh
mkdir -p dist
ZIP="dist/AirfryerMac-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "build/Airfryer Mac.app" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "Release archive: $ZIP"
