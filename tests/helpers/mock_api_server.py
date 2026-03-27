#!/usr/bin/env python3
"""Minimal mock HTTP server for testing the Netweak agent.

Logs all POST requests (path + body) to a file for assertion by BATS tests.
Serves local files when GET requests match /raw/<filename> (for install.sh tests).
Handles agent API endpoints (get-token, check-token) with test-specific responses.

Usage:
    python3 mock_api_server.py [port] [serve_dir]

Environment:
    MOCK_API_LOG  — path to request log file (default: /tmp/mock_api_requests.log)
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs
import json
import os
import sys


REQUESTS_LOG = os.environ.get("MOCK_API_LOG", "/tmp/mock_api_requests.log")
SERVE_DIR = None


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8", errors="replace")
        with open(REQUESTS_LOG, "a") as f:
            f.write(json.dumps({"path": self.path, "body": body}) + "\n")

        if self.path == "/agent/get-token":
            self._handle_get_token(body)
        elif self.path == "/agent/check-token":
            self._handle_check_token(body)
        else:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')

    def _handle_get_token(self, body):
        team_token = self._parse_field(body, "team_token")

        if team_token == "team_invalid":
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b'{"message":"Invalid team token"}')
        elif team_token == "team_limit_reached":
            self.send_response(403)
            self.end_headers()
            self.wfile.write(json.dumps({
                "error": "PlanLimitReached",
                "message": "Server limit reached for this team's billing plan.",
                "documentation": "https://netweak.com/pricing",
            }).encode())
        else:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"token":"mock_server_token_abc123"}')

    def _handle_check_token(self, body):
        token = self._parse_field(body, "token")

        if token == "invalid_token":
            self.send_response(401)
            self.end_headers()
            self.wfile.write(b'{"valid":false,"message":"Token is incorrect or server has been deleted."}')
        else:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"valid":true}')

    def _parse_field(self, body, field):
        """Parse a field from JSON or form-encoded body."""
        try:
            data = json.loads(body)
            return data.get(field, "")
        except (json.JSONDecodeError, ValueError):
            pass
        parsed = parse_qs(body)
        values = parsed.get(field, [""])
        return values[0]

    def do_GET(self):
        # Serve local files for install.sh download tests
        if SERVE_DIR and self.path.startswith("/raw/"):
            filename = self.path.split("/raw/", 1)[1]
            filepath = os.path.join(SERVE_DIR, filename)
            if os.path.isfile(filepath):
                self.send_response(200)
                self.end_headers()
                with open(filepath, "rb") as f:
                    self.wfile.write(f.read())
                return
        self.send_response(404)
        self.end_headers()

    def log_message(self, *args):
        pass  # Suppress stderr


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8089
    SERVE_DIR = sys.argv[2] if len(sys.argv) > 2 else None

    # Clear previous log
    open(REQUESTS_LOG, "w").close()

    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"Mock API server on port {port}", flush=True)
    server.serve_forever()
