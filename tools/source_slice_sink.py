"""Local HTTP sink so Studio can POST bulk data straight to disk.

Returning a large dump through `execute_luau`'s return value costs one read per
~46 KB and a lot of context. Studio's HttpService reaches localhost from the MCP
plugin's context, so a two-minute sink is far cheaper: 231 KB of measured
building extents moved in a single call.

  python tools/source_slice_sink.py            # serves until interrupted

Then, in Studio (Command Bar or execute_luau):

  local H = game:GetService("HttpService")
  H:RequestAsync({Url = "http://127.0.0.1:58999/live_extents.csv",
                  Method = "POST", Body = text})

The path becomes the filename under tools/source_slices (sanitised). Send
X-Append: 1 to append rather than overwrite, for dumps built in several calls.

GET goes the other way, for data too big to paste into a call:

  local body = game:GetService("HttpService"):GetAsync(
      "http://127.0.0.1:58999/get/src/server/SourceSliceCrowns.json")

Paths under /get/ are read relative to the repo root and may not escape it.
"""
import http.server
import pathlib
import socketserver

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = pathlib.Path(__file__).resolve().parent / "source_slices"
PORT = 58999


class Sink(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        name = self.path.strip("/") or "dump.txt"
        name = "".join(c for c in name if c.isalnum() or c in "._-")
        mode = "ab" if self.headers.get("X-Append") == "1" else "wb"
        with open(OUT / name, mode) as fh:
            fh.write(body)
        print(f"{name}: {len(body)} bytes ({'appended' if mode == 'ab' else 'written'})",
              flush=True)
        self.send_response(200)
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    def do_GET(self):
        if not self.path.startswith("/get/"):
            self.send_error(404)
            return
        try:
            target = (ROOT / self.path[5:]).resolve()
            target.relative_to(ROOT)          # refuse to serve outside the repo
            body = target.read_bytes()
        except (OSError, ValueError):
            self.send_error(404)
            return
        print(f"GET {self.path[5:]}: {len(body)} bytes", flush=True)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def main():
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("127.0.0.1", PORT), Sink) as server:
        print(f"sink on 127.0.0.1:{PORT} -> {OUT}", flush=True)
        server.serve_forever()


if __name__ == "__main__":
    main()
