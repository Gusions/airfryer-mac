#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Airfryer Mac contributors. See the LICENSE file.
"""Fake Home Assistant to try the app without an air fryer. It never talks to real devices.

Usage: python3 mock_ha.py [port]   (default 8123, valid token: test-token)
GET /api/states, POST /api/services/<domain>/<service>; the call log is at GET /_log.
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

TOKEN = "test-token"
LOG = []


def ent(eid, state, **attrs):
    return {"entity_id": eid, "state": state, "attributes": attrs}


STATES = [
    ent("sensor.philips_airfryer_status", "idle", friendly_name="Philips Airfryer Status"),
    ent("sensor.philips_airfryer_time_remaining", "0", friendly_name="Philips Airfryer Time remaining", unit_of_measurement="min"),
    ent("number.philips_airfryer_temperature", "180", friendly_name="Philips Airfryer Temperature", unit_of_measurement="°C", min=40, max=200, step=5),
    ent("number.philips_airfryer_cook_time", "900", friendly_name="Philips Airfryer Cook time", unit_of_measurement="s", min=60, max=3600, step=60),
    ent("number.philips_airfryer_keep_warm_duration", "10", friendly_name="Philips Airfryer Keep warm duration", unit_of_measurement="min", min=1, max=30, step=1),
    ent("button.philips_airfryer_start", "unknown", friendly_name="Philips Airfryer Start"),
    ent("button.philips_airfryer_pause", "unknown", friendly_name="Philips Airfryer Pause"),
    ent("button.philips_airfryer_stop", "unknown", friendly_name="Philips Airfryer Stop"),
    # Entities of other devices: they must not be matched automatically.
    ent("number.cucina_temperature", "21", friendly_name="Kitchen thermostat Temperature", unit_of_measurement="°C", min=5, max=30, step=1),
    ent("button.garage_start", "unknown", friendly_name="Garage Start"),
]


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _auth(self):
        if self.headers.get("Authorization") != f"Bearer {TOKEN}":
            self._send(401, {"message": "401: Unauthorized"})
            return False
        return True

    def _send(self, code, obj):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/_log":
            return self._send(200, LOG)
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "http://127.0.0.1:1/")
            self.end_headers()
            return
        if not self._auth():
            return
        if self.path == "/api/states":
            return self._send(200, STATES)
        self._send(404, {})

    def do_POST(self):
        if not self._auth():
            return
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        if self.path.startswith("/api/services/"):
            LOG.append({"service": self.path[len("/api/services/"):], "body": body})
            return self._send(200, [])
        self._send(404, {})


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8123
    HTTPServer(("127.0.0.1", port), H).serve_forever()
