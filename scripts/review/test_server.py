"""Checks the review server's access boundary and stale-frame handling without a browser."""

import http.client
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest

from server import ReviewServer


class ReviewServerTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.server = ReviewServer(self.folder.name)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.folder.cleanup()

    def request(self, route="", headers=None, method="GET", token=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)
        connection.request(method, f"/{token or self.server.token}/{route}", headers=headers or {})
        response = connection.getresponse()
        result = response.status, dict(response.getheaders()), response.read()
        connection.close()
        return result

    def write_snapshot(self, age=0):
        data = {"capturedAt": time.time() - age, "elements": [], "image": "private capture"}
        Path(self.folder.name, "snapshot.json").write_text(json.dumps(data))
        return data

    def test_authenticated_page_and_frame_are_not_cached(self):
        self.assertEqual(self.server.server_address[0], "127.0.0.1")
        status, headers, html = self.request()
        self.assertEqual(status, 200)
        self.assertIn(b'Native view hierarchy', html)
        self.assertEqual(headers["Cache-Control"], "no-store")
        self.assertEqual(headers["Referrer-Policy"], "no-referrer")
        self.assertIn("frame-ancestors 'none'", headers["Content-Security-Policy"])
        expected = self.write_snapshot()
        status, headers, data = self.request("snapshot.json")
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(data), expected)
        self.assertNotIn("Access-Control-Allow-Origin", headers)

    def test_missing_or_wrong_token_cannot_read_frames(self):
        self.write_snapshot()
        for token in ["wrong", "", "../"]:
            # Use a raw connection for the empty-token case.
            connection = http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)
            connection.request("GET", f"/{token}/snapshot.json")
            response = connection.getresponse()
            self.assertEqual(response.status, 404)
            self.assertNotIn(b"private capture", response.read())
            connection.close()

    def test_host_origin_and_fetch_site_are_checked(self):
        for headers in [
            {"Host": "evil.example"},
            {"Origin": "https://evil.example"},
            {"Sec-Fetch-Site": "cross-site"},
        ]:
            self.assertEqual(self.request(headers=headers)[0], 403)
        self.assertEqual(self.request(headers={"Origin": self.server.origin})[0], 200)

    def test_only_fixed_assets_are_exposed(self):
        for route in ["../server.py", "%2e%2e/server.py", "server.py", "pid", "stop", "sample.md"]:
            self.assertEqual(self.request(route)[0], 404)
        self.assertEqual(self.request("review.js")[0], 200)
        self.assertEqual(self.request("review.css")[0], 200)

    def test_unavailable_corrupt_and_stale_frames_are_reported(self):
        self.assertEqual(self.request("snapshot.json")[0], 503)
        Path(self.folder.name, "snapshot.json").write_text("{")
        self.assertEqual(self.request("snapshot.json")[0], 503)
        self.write_snapshot(age=30)
        self.assertEqual(self.request("snapshot.json")[0], 503)
        self.write_snapshot()
        self.assertEqual(self.request("snapshot.json")[0], 200)

    def test_no_write_api(self):
        self.assertEqual(self.request("stop", method="POST")[0], 501)
        self.assertFalse(Path(self.folder.name, "stop").exists())


if __name__ == "__main__":
    unittest.main()
