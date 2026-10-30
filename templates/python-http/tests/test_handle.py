import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import main  # noqa: E402


def test_handle_zwraca_200():
    status, out = main.handle("GET", "/", b"")
    assert status == 200 and out["path"] == "/"
