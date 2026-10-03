#!/usr/bin/env python3
"""Serve only the current arm64 APK, without caching old builds."""

import argparse
import os
import shutil
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit


class ApkHandler(BaseHTTPRequestHandler):
    apk_path: Path

    def do_HEAD(self):
        self._serve(send_body=False)

    def do_GET(self):
        self._serve(send_body=True)

    def _serve(self, *, send_body: bool):
        if urlsplit(self.path).path != "/xudian.apk":
            self.send_error(404, "Not found")
            return

        try:
            apk = self.apk_path.open("rb")
        except OSError:
            self.send_error(503, "APK is temporarily unavailable")
            return

        with apk:
            size = os.fstat(apk.fileno()).st_size
            self.send_response(200)
            self.send_header("Content-Type", "application/vnd.android.package-archive")
            self.send_header("Content-Disposition", 'attachment; filename="xudian.apk"')
            self.send_header("Content-Length", str(size))
            self.send_header("Cache-Control", "no-store, max-age=0")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            if send_body:
                try:
                    shutil.copyfileobj(apk, self.wfile)
                except (BrokenPipeError, ConnectionResetError):
                    pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apk", type=Path)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    ApkHandler.apk_path = args.apk.resolve()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), ApkHandler)
    server.serve_forever()


if __name__ == "__main__":
    main()
