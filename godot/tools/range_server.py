#!/usr/bin/env python3
"""A small file server with byte ranges, for testing the content loader on desktop (tools/content_e2e.sh).
  python3 tools/range_server.py DIR PORT [--drop-after BYTES] [--rate BYTES_PER_S]
--drop-after: the first response that would pass that many bytes served in total is cut off mid-body (a dropped
connection), once. --rate: throttle, so the progress can be watched."""
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = sys.argv[1]
PORT = int(sys.argv[2])
DROP = int(sys.argv[sys.argv.index("--drop-after") + 1]) if "--drop-after" in sys.argv else -1
RATE = int(sys.argv[sys.argv.index("--rate") + 1]) if "--rate" in sys.argv else 0
served = [0, False]


class H(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        sys.stderr.write("range_server: " + (fmt % args) + "\n")

    def do_GET(self):
        path = os.path.join(ROOT, os.path.basename(self.path.split("?")[0]))
        if not os.path.isfile(path):
            self.send_error(404)
            return
        size = os.path.getsize(path)
        start, end = 0, size - 1
        rng = self.headers.get("Range")
        if rng and rng.startswith("bytes="):
            a, b = rng[6:].split("-")
            start = int(a)
            end = min(int(b), size - 1) if b else size - 1
            self.send_response(206)
            self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, size))
        else:
            self.send_response(200)
        n = end - start + 1
        self.send_header("Content-Length", str(n))
        self.send_header("Content-Type", "application/octet-stream")
        self.end_headers()
        with open(path, "rb") as f:
            f.seek(start)
            left = n
            while left > 0:
                chunk = f.read(min(1 << 16, left))
                if DROP >= 0 and not served[1] and served[0] + len(chunk) > DROP:
                    served[1] = True
                    self.wfile.write(chunk[: max(0, DROP - served[0])])
                    self.wfile.flush()
                    self.connection.close()
                    sys.stderr.write("range_server: dropped the connection at %d bytes\n" % DROP)
                    return
                self.wfile.write(chunk)
                served[0] += len(chunk)
                left -= len(chunk)
                if RATE:
                    time.sleep(len(chunk) / RATE)


ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
