#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Airfryer Mac contributors. See the LICENSE file.
# Double-click to build and open Airfryer Mac (the Italian name is kept for compatibility with older instructions).
cd "$(dirname "$0")"
if bash Tools/build.sh; then
  echo "You can drag the app from the build folder to Applications."
  open "build/Airfryer Mac.app"
else
  read -r -p "Press Return to close."
  exit 1
fi
