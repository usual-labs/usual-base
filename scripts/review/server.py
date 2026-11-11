#!/usr/bin/env python3
"""Serve a single opt-in Debug review session on loopback; no remote input API."""

import argparse
import http.server
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import time

ASSETS = Path(__file__).resolve().parent
ROUTES = {
    "": ("index.html", "text/html; charset=utf-8"),
    "review.js": ("review.js", "text/javascript; charset=utf-8"),
    "review.css": ("review.css", "text/css; charset=utf-8"),
}


class ReviewServer(http.server.HTTPServer):
    def __init__(self, folder):
        self.folder = Path(folder)
        self.token = secrets.token_urlsafe(32)
        super().__init__(("127.0.0.1", 0), ReviewHandler)
        self.origin = f"http://127.0.0.1:{self.server_port}"
        self.url = f"{self.origin}/{self.token}/"
        self.timeout = 0.3

    def get_request(self):
        connection, address = super().get_request()
        connection.settimeout(2)
        return connection, address


class ReviewHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Never log capability URLs or note contents.

    def do_GET(self):
        if self.headers.get("Host") != self.server.origin.removeprefix("http://"):
            return self.reply(403, b"Unexpected host")
        origin = self.headers.get("Origin")
        if origin and origin != self.server.origin:
            return self.reply(403, b"Unexpected origin")
        if self.headers.get("Sec-Fetch-Site") == "cross-site":
            return self.reply(403, b"Cross-site requests are not allowed")
        parts = self.path.split("/")
        if len(parts) != 3 or not secrets.compare_digest(parts[1], self.server.token):
            return self.reply(404, b"Not found")
        route = parts[2]
        if route == "snapshot.json":
            try:
                data = self.server.folder.joinpath("snapshot.json").read_bytes()
                snapshot = json.loads(data)
                if time.time() - snapshot["capturedAt"] > 8:
                    return self.reply(503, b"No recent frame. Keep the review app window open and visible.")
                return self.reply(200, data, "application/json")
            except (OSError, ValueError, KeyError, TypeError):
                return self.reply(503, b"Waiting for the review app's first frame.")
        if route not in ROUTES:
            return self.reply(404, b"Not found")
        filename, mime = ROUTES[route]
        self.reply(200, ASSETS.joinpath(filename).read_bytes(), mime)

    def reply(self, status, data, mime="text/plain; charset=utf-8"):
        self.send_response(status)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header(
            "Content-Security-Policy",
            "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; "
            "img-src 'self' data:; connect-src 'self'; base-uri 'none'; "
            "form-action 'none'; frame-ancestors 'none'",
        )
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path)
    args = parser.parse_args()
    app = args.app.resolve()
    if not (app / "Contents/MacOS/UsualBase").is_file():
        parser.error(f"No built UsualBase app at {app}")
    os.umask(0o077)
    # Capture only disposable notes. The review build has its own bundle identifier and preferences.
    with tempfile.TemporaryDirectory(prefix="usual-base-review-") as directory:
        folder = Path(directory)
        base = folder / "Sample Base"
        base.mkdir()
        (base / "Welcome.md").write_text((ASSETS / "sample.md").read_text())
        (base / "Another note.md").write_text("# Another note\n\nChoose Welcome in the sidebar to return.\n")
        launcher = subprocess.Popen([
            "/usr/bin/open", "-n", "-W", "--env", f"USUALBASE_REVIEW={folder}",
            "--env", f"USUALBASE_OPEN={base}", "--env", "USUALBASE_FILE=Welcome.md",
            "--env", "USUALBASE_MODE=view", str(app),
        ])
        with ReviewServer(folder) as server:
            print(f"Review URL: {server.url}", flush=True)
            print("Use the native sample app to navigate; select and comment in the browser.", flush=True)
            print("Ctrl-C closes this review app and removes its temporary notes and captures.", flush=True)
            try:
                while launcher.poll() is None:
                    server.handle_request()
            except KeyboardInterrupt:
                pass
            finally:
                # The probe calls NSApp.terminate so normal save-on-quit behavior runs.
                # No process-name kill: other Usual Base instances belong to the user.
                (folder / "stop").touch()
                try:
                    launcher.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    print("The review app has not exited; close its sample window manually.", flush=True)


if __name__ == "__main__":
    main()
