"""Szablon funkcji HTTP MemeOps: zmień tylko handle()."""
import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def handle(method, path, body):
    """Logika funkcji. Zwraca (status, dict)."""
    return 200, {"hello": os.environ.get("GREETING", "MemeOps"), "path": path}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _serve(self):
        t0 = time.time()
        if self.path == "/healthz":
            status, out = 200, {"ok": True}
        else:
            body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
            status, out = handle(self.command, self.path, body)
        data = json.dumps(out).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        if self.path != "/healthz":
            print(json.dumps({"method": self.command, "path": self.path, "status": status,
                              "ms": round((time.time() - t0) * 1000, 1),
                              "rev": os.environ.get("K_REVISION", "lokalnie")}), flush=True)

    do_GET = do_POST = _serve


if __name__ == "__main__":
    ThreadingHTTPServer(("", int(os.environ.get("PORT", "8080"))), Handler).serve_forever()
