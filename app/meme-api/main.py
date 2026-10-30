"""meme-api — MVP MemeOps: mem tekstowy (ASCII) z parametrów URL.

GET /?top=...&bottom=...   → mem jako tekst
GET /healthz               → ok
Wersję ustala obraz (build-arg VERSION): v1 = ASCII, v2 = ASCII + emoji.
"""
import json
import os
import socket
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

STARTED = time.time()
VERSION = os.environ.get("APP_VERSION", "v1")
REVISION = os.environ.get("K_REVISION", "lokalnie")
GREETING = os.environ.get("GREETING", "")


def meme(top, bottom):
    width = max(len(top), len(bottom), 20) + 4
    line = "+" + "-" * (width - 2) + "+"
    face = "   (•_•)\n   ( •_•)>⌐■-■\n   (⌐■_■)" if VERSION == "v1" else "   🤖 ➜ 😎 ➜ 🚀"
    rows = [line, "| " + top.upper().center(width - 4) + " |", line, face, line,
            "| " + bottom.upper().center(width - 4) + " |", line]
    return "\n".join(rows)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/healthz":
            body = b"ok"
        else:
            q = parse_qs(url.query)
            top = q.get("top", ["serverless"])[0][:40]
            bottom = q.get("bottom", ["skaluje do zera"])[0][:40]
            footer = f"\n\n[{VERSION} · {REVISION} · {socket.gethostname()} · uptime {time.time() - STARTED:.0f}s]"
            if GREETING:
                footer = f"\n{GREETING}" + footer
            body = (meme(top, bottom) + footer + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        print(json.dumps({"path": url.path, "rev": REVISION, "version": VERSION}), flush=True)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    print(json.dumps({"msg": "start", "version": VERSION, "port": port}), flush=True)
    ThreadingHTTPServer(("", port), Handler).serve_forever()
