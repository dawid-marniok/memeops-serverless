#!/usr/bin/env python3
"""Generator tokenów JWT dla uczestników konferencji MemeOps.

Użycie: tools/token.py <login> [ważność w minutach=120]
Klucz bierze ze zmiennej JWT_SECRET albo z Secretu w klastrze:
  export JWT_SECRET=$(kubectl -n memeops get secret meme-jwt -o jsonpath='{.data.JWT_SECRET}' | base64 -d)
"""
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "app" / "meme-gen"))
import auth  # noqa: E402

if len(sys.argv) < 2 or not os.environ.get("JWT_SECRET"):
    sys.exit(__doc__)
minutes = int(sys.argv[2]) if len(sys.argv) > 2 else 120
print(auth.sign({"sub": sys.argv[1], "exp": int(time.time()) + minutes * 60}, os.environ["JWT_SECRET"]))
