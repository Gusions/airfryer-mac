#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Airfryer Mac contributors. See the LICENSE file.
"""Checks that every localized string used in the Swift code has a key in keys.py (and vice versa)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from keys import KEYS  # noqa: E402

src = "".join(open(os.path.join(ROOT, "Sources", f), encoding="utf-8").read() for f in ("App.swift", "Core.swift"))
# Swift interpolations \(...) become %lld placeholders (every interpolation used is an Int).
used = set()
patterns = [r'\bL\("((?:[^"\\]|\\.)*)"', r'\b(?:Text|Button|Label|TextField|SecureField|DisclosureGroup|Picker)\("((?:[^"\\]|\\.)*)"',
            r'\.(?:help|alert)\("((?:[^"\\]|\\.)*)"', r'LocalizedStringKey\("((?:[^"\\]|\\.)*)"', r'stepper\(title: "((?:[^"\\]|\\.)*)"',
            r'Preset\(name: "((?:[^"\\]|\\.)*)"', r'return "((?:[^"\\]|\\.)*)"\n', r'case \.\w+: return "((?:[^"\\]|\\.)*)"']
for pat in patterns:
    for m in re.finditer(pat, src):
        used.add(re.sub(r"\\\(.*?\)\)?", "%lld", m.group(1)) if "\\(" in m.group(1) else m.group(1))
missing = sorted(k for k in used if k not in KEYS and not k.startswith(("http", "%", "—", "--")) and len(k) > 3 and not re.fullmatch(r"[a-z]+\.", k)
                 and k not in ("Airfryer", "°C", "standby", "idle", "off", "cooking", "preheating", "preheat", "paused", "pause", "finished", "done", "ready", "none"))
print("Strings in the code without a translation:", missing or "none")
unused = [k for k in KEYS if k not in src and k not in used]
print("Keys not present in the code:", unused or "none")
sys.exit(1 if missing or unused else 0)
