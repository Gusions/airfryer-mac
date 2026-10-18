#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Airfryer Mac contributors. See the LICENSE file.
# Builds "build/Airfryer Mac.app" (Apple Silicon, macOS 14+). Usage: Tools/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."
if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "The free Apple Command Line Tools are required. Run: xcode-select --install"
  exit 1
fi
if [ "$(uname -m)" != "arm64" ]; then
  echo "This package targets Apple Silicon Macs. Open Terminal without Rosetta."
  exit 1
fi
APP="$PWD/build/Airfryer Mac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
echo "Compiling Airfryer Mac…"
LOG="$(mktemp)"
if ! xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macosx14.0 \
  Sources/Core.swift Sources/App.swift -o "$APP/Contents/MacOS/AirfryerMac" 2>"$LOG"; then
  if grep -q "this SDK is not supported by the compiler\|redefinition of module 'SwiftBridging'" "$LOG"; then
    echo "The Command Line Tools are out of date for this macOS."
    echo "Open System Settings > General > Software Update and install \"Command Line Tools for Xcode\"."
  else
    cat "$LOG"
    echo "Build failed. Please include the message above when reporting the problem."
  fi
  exit 1
fi
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/MenuBarIcon.png "Resources/MenuBarIcon@2x.png" "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built: $APP"
