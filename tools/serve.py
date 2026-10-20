#!/usr/bin/env python3
"""Dev server: correct MIME types for wasm/mjs/woff2/task, and no caching of sw.js."""
import functools
import http.server
import socketserver
import sys

TYPES = {
    ".wasm": "application/wasm",
    ".mjs": "text/javascript",
    ".js": "text/javascript",
    ".css": "text/css",
    ".json": "application/json",
    ".task": "application/octet-stream",
    ".woff2": "font/woff2",
    ".webmanifest": "application/manifest+json",
    ".heic": "image/heic",
}


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=".", **kw)

    def guess_type(self, path):
        for ext, mime in TYPES.items():
            if path.endswith(ext):
                return mime
        return super().guess_type(path)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("  %s\n" % (fmt % args))


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
    with Server(("0.0.0.0", port), Handler) as httpd:
        print("listening on 0.0.0.0:%d" % port)
        httpd.serve_forever()


if __name__ == "__main__":
    main()
