"""Serve the map viewer on http://127.0.0.1:8765 (local only).

Usage:
    python -I serve.py [--world DIR] [--port 8765]

`--world` is the folder holding world.json and the .glb chunks (default <work>\\world). It's served at
/world/ so game-derived files never need to live in this repo. Without it, the viewer shows test terrain.
"""
import argparse
import functools
import http.server
import os

HERE = os.path.dirname(os.path.abspath(__file__))


class Handler(http.server.SimpleHTTPRequestHandler):
    world = None

    def translate_path(self, path):
        clean = path.split("?", 1)[0].split("#", 1)[0]
        if self.world and clean.startswith("/world/"):
            rel = os.path.normpath(clean[len("/world/"):]).lstrip("\\/")
            if rel.startswith(".."):
                return os.path.join(self.world, "__denied__")
            return os.path.join(self.world, rel)
        return super().translate_path(path)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--world", default=r"<work>\world")
    ap.add_argument("--port", type=int, default=8765)
    a = ap.parse_args()
    Handler.world = a.world if os.path.isdir(a.world) else None
    Handler.extensions_map[".glb"] = "model/gltf-binary"
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", a.port), functools.partial(Handler, directory=HERE))
    print(f"viewer: http://127.0.0.1:{a.port}/  world: {Handler.world or '(none: test terrain)'}", flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
