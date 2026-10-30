"""Minimalna weryfikacja JWT HS256 (biblioteka standardowa, bez PyJWT).

Na produkcji użyj sprawdzonej biblioteki albo uwierzytelniania na ingressie (oauth2-proxy).
Tu chodzi o to, skąd funkcja bierze klucz: z Secretu, nie z kodu.
"""
import base64
import hashlib
import hmac
import json
import time


class AuthError(Exception):
    pass


def _b64d(part):
    return base64.urlsafe_b64decode(part + "=" * (-len(part) % 4))


def _b64e(raw):
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def sign(claims, secret):
    header = _b64e(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    payload = _b64e(json.dumps(claims).encode())
    sig = hmac.new(secret.encode(), f"{header}.{payload}".encode(), hashlib.sha256).digest()
    return f"{header}.{payload}.{_b64e(sig)}"


def verify(authorization, secret):
    if not authorization.startswith("Bearer "):
        raise AuthError("brak tokenu: Authorization: Bearer <JWT>")
    token = authorization[len("Bearer "):].strip()
    try:
        header, payload, sig = token.split(".")
        if json.loads(_b64d(header)).get("alg") != "HS256":
            raise AuthError("obsługuję tylko HS256")
        expected = hmac.new(secret.encode(), f"{header}.{payload}".encode(), hashlib.sha256).digest()
        if not hmac.compare_digest(expected, _b64d(sig)):
            raise AuthError("zły podpis tokenu")
        claims = json.loads(_b64d(payload))
    except AuthError:
        raise
    except Exception as e:  # noqa: BLE001
        raise AuthError("token nieczytelny") from e
    if claims.get("exp", 0) < time.time():
        raise AuthError("token wygasł")
    return claims
