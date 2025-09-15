#!/usr/bin/env python3
"""
Minimal static web server for this repository.

- Serves files from the chosen directory (default: repo root).
- Exposes a health endpoint at /healthz returning "ok".
- Designed for local dev and container use (HOST/PORT envs).
"""

import argparse
import http.server
import logging
import os
import socketserver
from functools import partial


class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/health", "/healthz", "/_health"):
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"ok")
            return
        return super().do_GET()

    def log_message(self, fmt, *args):
        logging.info("%s - - [%s] %s", self.client_address[0], self.log_date_time_string(), fmt % args)


def main():
    parser = argparse.ArgumentParser(description="Serve the static index.html for local dev and containers.")
    parser.add_argument("--host", default=os.environ.get("HOST", "0.0.0.0"), help="Bind address (default 0.0.0.0)")
    parser.add_argument("--port", type=int, default=int(os.environ.get("PORT", "8000")), help="Port to listen on")
    parser.add_argument(
        "--dir",
        default=os.environ.get("ROOT_DIR", os.getcwd()),
        help="Directory to serve (default: current working directory)",
    )
    args = parser.parse_args()

    # Ensure index exists for clarity in logs (not required to run).
    index_path = os.path.join(args.dir, "index.html")
    if not os.path.exists(index_path):
        logging.warning("index.html not found in %s; directory listing will be served.", args.dir)

    logging.basicConfig(level=logging.INFO, format="%(message)s")
    os.chdir(args.dir)

    handler_cls = partial(Handler, directory=args.dir)

    with socketserver.TCPServer((args.host, args.port), handler_cls) as httpd:
        logging.info("Serving %s at http://%s:%s", args.dir, args.host, args.port)
        logging.info("Health endpoint: http://%s:%s/healthz", args.host, args.port)
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            logging.info("Shutting down...")
        finally:
            httpd.server_close()


if __name__ == "__main__":
    main()

