"""meme-gen — generator memów MemeOps (funkcja HTTP dla Knative).

Konfiguracja tylko przez zmienne środowiskowe (manifest, ConfigMap, Secret):
  PORT          port HTTP (Knative ustawia 8080)
  MEME_FORMAT   svg (domyślnie, bez zależności) | png (wymaga Pillow)
  THEME         light (domyślnie) | dark
  WATERMARK     tekst znaku wodnego w rogu mema (np. z ConfigMap)
  JWT_SECRET    gdy ustawiony: POST /api/memes wymaga nagłówka Authorization: Bearer <JWT HS256>
  APP_VERSION   wersja aplikacji pokazywana w /api/info

Endpointy:
  GET  /                 strona z formularzem
  GET  /healthz          200 OK (sonda)
  GET  /api/info         wersja, rewizja Knative, format, czas od startu procesu
  POST /api/memes        {"top", "bottom", "template", "scale"} → {"id", "url"}
  GET  /api/memes        galeria (lista id, w pamięci procesu)
  GET  /api/memes/<id>   obrazek
"""
import json
import os
import socket
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import auth
import memes

STARTED = time.time()
CONFIG = {
    "format": os.environ.get("MEME_FORMAT", "svg").lower(),
    "theme": os.environ.get("THEME", "light").lower(),
    "watermark": os.environ.get("WATERMARK", ""),
    "version": os.environ.get("APP_VERSION", "dev"),
    "revision": os.environ.get("K_REVISION", "lokalnie"),
    "jwt_secret": os.environ.get("JWT_SECRET", ""),
}
GALLERY = {}  # id → (content_type, bytes); znika razem z podem (scale-to-zero!)
GALLERY_MAX = 50
_lock = threading.Lock()
INDEX = (Path(__file__).parent / "static" / "index.html").read_bytes()


def log(**fields):
    fields["ts"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    fields["rev"] = CONFIG["revision"]
    print(json.dumps(fields, ensure_ascii=False), flush=True)


class Handler(BaseHTTPRequestHandler):
    server_version = "meme-gen"

    def log_message(self, *args):  # własne logi JSON zamiast domyślnych
        pass

    def _send(self, status, body, ctype="application/json"):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        self._status = status

    def _route(self):
        path = self.path.split("?", 1)[0]
        if self.command == "GET" and path == "/":
            return self._send(200, INDEX, "text/html; charset=utf-8")
        if self.command == "GET" and path == "/healthz":
            return self._send(200, b"ok", "text/plain")
        if self.command == "GET" and path == "/api/info":
            return self._send(200, {
                "app": "meme-gen", "version": CONFIG["version"], "revision": CONFIG["revision"],
                "format": CONFIG["format"], "theme": CONFIG["theme"], "auth": bool(CONFIG["jwt_secret"]),
                "pod": socket.gethostname(), "uptime_s": round(time.time() - STARTED, 1),
            })
        if self.command == "GET" and path == "/api/memes":
            with _lock:
                ids = list(GALLERY)
            return self._send(200, {"memes": [f"/api/memes/{i}" for i in ids], "pod": socket.gethostname()})
        if self.command == "GET" and path.startswith("/api/memes/"):
            item = GALLERY.get(path.rsplit("/", 1)[-1])
            if not item:
                return self._send(404, {"error": "nie ma takiego mema (może pod został wyłączony?)"})
            return self._send(200, item[1], item[0])
        if self.command == "POST" and path == "/api/memes":
            return self._create()
        return self._send(404, {"error": "nie znaleziono"})

    def _create(self):
        if CONFIG["jwt_secret"]:
            try:
                claims = auth.verify(self.headers.get("Authorization", ""), CONFIG["jwt_secret"])
            except auth.AuthError as e:
                return self._send(401, {"error": str(e)})
            self._user = claims.get("sub", "?")
        try:
            length = int(self.headers.get("Content-Length") or 0)
            data = json.loads(self.rfile.read(length) or b"{}")
            scale = min(max(int(data.get("scale", 1)), 1), 8)
        except (ValueError, TypeError):
            return self._send(400, {"error": "oczekuję JSON: top, bottom, template, scale (1-8)"})
        ctype, body = memes.render(
            fmt=CONFIG["format"], top=str(data.get("top", "")), bottom=str(data.get("bottom", "")),
            template=str(data.get("template", "keynote")), theme=CONFIG["theme"],
            watermark=CONFIG["watermark"], scale=scale,
        )
        meme_id = uuid.uuid4().hex[:10]
        with _lock:
            GALLERY[meme_id] = (ctype, body)
            while len(GALLERY) > GALLERY_MAX:
                GALLERY.pop(next(iter(GALLERY)))
        return self._send(201, {"id": meme_id, "url": f"/api/memes/{meme_id}", "format": CONFIG["format"],
                                "revision": CONFIG["revision"]})

    def _handle(self):
        t0, self._status, self._user = time.time(), 500, None
        try:
            self._route()
        except Exception as e:  # noqa: BLE001 — każdy błąd ma trafić do logu jako JSON
            log(level="error", path=self.path, error=repr(e))
            if self._status == 500:
                self._send(500, {"error": "błąd serwera"})
        finally:
            if self.path != "/healthz":
                log(method=self.command, path=self.path.split("?", 1)[0], status=self._status,
                    ms=round((time.time() - t0) * 1000, 1), user=self._user)

    do_GET = do_POST = _handle


def main():
    if CONFIG["format"] == "png" and not memes.HAS_PILLOW:
        log(level="fatal", error="MEME_FORMAT=png, ale Pillow nie jest zainstalowany (requirements.txt)")
        sys.exit(1)
    port = int(os.environ.get("PORT", "8080"))
    log(level="info", msg="start", port=port, format=CONFIG["format"], theme=CONFIG["theme"],
        version=CONFIG["version"], startup_ms=round((time.time() - STARTED) * 1000, 1))
    ThreadingHTTPServer(("", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
