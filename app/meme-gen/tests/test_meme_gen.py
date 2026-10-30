"""Testy funkcji meme-gen. Uruchom: cd app/meme-gen && python -m pytest -q"""
import json
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import auth  # noqa: E402
import memes  # noqa: E402


def test_svg_zawiera_tekst_wielkimi_literami():
    svg = memes.render_svg("KIEDY DEPLOY", "W PIĄTEK", "piatek", "light", "", 1)
    assert "KIEDY DEPLOY" in svg and "W PIĄTEK" in svg
    assert svg.startswith("<svg")


def test_svg_escapuje_html():
    ctype, body = memes.render("svg", "<script>", "&", "keynote")
    assert ctype == "image/svg+xml"
    assert b"<script>" not in body and b"&lt;SCRIPT&gt;" in body


def test_znak_wodny_i_ciemny_motyw():
    svg = memes.render_svg("A", "B", "keynote", "dark", "#DevConf2026", 1)
    assert "#DevConf2026" in svg
    assert memes.palette("keynote", "dark")[3] == "#7CFFB2"


@pytest.mark.skipif(not memes.HAS_PILLOW, reason="Pillow niezainstalowany (wersja SVG)")
def test_png_ma_naglowek_png():
    ctype, body = memes.render("png", "A", "B", "kawa")
    assert ctype == "image/png" and body[:8] == b"\x89PNG\r\n\x1a\n"


def test_jwt_poprawny_token():
    token = auth.sign({"sub": "ania", "exp": time.time() + 60}, "tajne")
    assert auth.verify(f"Bearer {token}", "tajne")["sub"] == "ania"


@pytest.mark.parametrize("header,msg", [
    ("", "brak tokenu"),
    ("Bearer abc", "nieczytelny"),
])
def test_jwt_odrzuca_smieci(header, msg):
    with pytest.raises(auth.AuthError, match=msg):
        auth.verify(header, "tajne")


def test_jwt_zly_klucz_i_wygasly():
    token = auth.sign({"sub": "x", "exp": time.time() + 60}, "inny-klucz")
    with pytest.raises(auth.AuthError, match="podpis"):
        auth.verify(f"Bearer {token}", "tajne")
    old = auth.sign({"sub": "x", "exp": time.time() - 1}, "tajne")
    with pytest.raises(auth.AuthError, match="wygasł"):
        auth.verify(f"Bearer {old}", "tajne")


@pytest.fixture(scope="module")
def serwer():
    import main
    from http.server import ThreadingHTTPServer
    srv = ThreadingHTTPServer(("127.0.0.1", 0), main.Handler)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{srv.server_address[1]}", main
    srv.shutdown()


def _post(url, data, token=None):
    req = urllib.request.Request(url, data=json.dumps(data).encode(), method="POST",
                                 headers={"Content-Type": "application/json",
                                          **({"Authorization": f"Bearer {token}"} if token else {})})
    return urllib.request.urlopen(req)


def test_http_tworzy_mema_i_galeria(serwer):
    base, main = serwer
    main.CONFIG["jwt_secret"] = ""
    r = json.load(_post(f"{base}/api/memes", {"top": "a", "bottom": "b"}))
    img = urllib.request.urlopen(base + r["url"])
    assert img.headers["Content-Type"] == "image/svg+xml"
    assert r["url"] in json.load(urllib.request.urlopen(f"{base}/api/memes"))["memes"]


def test_http_wymaga_tokenu_gdy_jest_sekret(serwer):
    base, main = serwer
    main.CONFIG["jwt_secret"] = "tajne"
    with pytest.raises(urllib.error.HTTPError) as e:
        _post(f"{base}/api/memes", {"top": "a"})
    assert e.value.code == 401
    token = auth.sign({"sub": "ania", "exp": time.time() + 60}, "tajne")
    assert _post(f"{base}/api/memes", {"top": "a"}, token).status == 201
    main.CONFIG["jwt_secret"] = ""
