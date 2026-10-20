#!/usr/bin/env python3
"""Serve the assembled Pages site the way GitHub Pages resolves paths, for local previews."""

import argparse
import functools
import http.server
import pathlib


class PagesHandler(http.server.SimpleHTTPRequestHandler):
    """Resolve extensionless paths to .html files and answer missing paths with the root 404.html."""

    def send_head(self):
        path = pathlib.Path(self.translate_path(self.path))
        if not path.exists() and path.with_suffix(".html").is_file():
            self.path = self.path.split("?", 1)[0] + ".html"
        elif not path.exists():
            not_found = next(pathlib.Path(self.directory).glob("*/404.html"), None)
            if not_found:
                body = not_found.read_bytes()
                self.send_response(404)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return None
        return super().send_head()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", help="directory that contains the <repo>/ site folder")
    parser.add_argument("--port", type=int, default=3000)
    args = parser.parse_args()
    handler = functools.partial(PagesHandler, directory=args.directory)
    with http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler) as server:
        print(f"Serving {args.directory} at http://127.0.0.1:{args.port}/")
        server.serve_forever()


if __name__ == "__main__":
    main()
