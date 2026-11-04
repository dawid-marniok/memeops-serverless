# lab03 — Funkcja w Pythonie: szablony, rejestr, wersje

| Dzień | Po bloku |
|---|---|
| 1 | 1.5 Funkcja Python, szablony, repozytoria, wersjonowanie |

> **Zgłoszenie od PO:** „MVP z ASCII to za mało. Chcemy własny generator memów, zbudowany tak, jak każda funkcja w firmie — i chcemy zawsze wiedzieć, który kod działa na produkcji.”

**Cel:** budujesz funkcję na dwa sposoby (`func` i szablon firmowy), publikujesz obraz w rejestrze z wersją i SHA commita, wdrażasz `meme-gen` i cofasz wersję.

**Zasada:** tag obrazu to obietnica, digest to fakt.

## Kroki

| # | Co robisz |
|---|---|
| A | Funkcja z `func` (szablon upstream) + własna zmiana w `handle()` |
| B | `meme-gen` z szablonu firmowego |
| C | Nowa wersja i rollback |
| D | Pułapka: nadpisany tag |

### A. Funkcja z `func`

```bash
cd ~ && func create -l python hello-fn && cd hello-fn
ls -R; cat func.yaml
func deploy --builder=host --registry localhost:5001 --registry-insecure --namespace memeops
curl http://hello-fn.memeops.127.0.0.1.sslip.io/
kubectl get ksvc hello-fn -n memeops -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
cd ~/memeops
```

`--builder=host` buduje obraz bez Dockera. Zwróć uwagę na **adres obrazu**: `func` wdraża po digeście (`@sha256:…`), nie po tagu.
Porównaj strukturę z [`templates/python-http/`](../../templates/python-http/): co daje szablon upstream, a co szablon firmowy?
Czym jest handler i czym różni się od zwykłego kontenera: [`demo/05-func/handler-vs-kontener.md`](../../demo/05-func/handler-vs-kontener.md).

**Gdzie piszesz kod?** W `function/func.py`, w metodzie `handle()` klasy `Function`. Reszta to otoczka:

| Plik | Do czego |
|---|---|
| `function/func.py` | **twój kod**: `handle()` przy każdym żądaniu, `start(cfg)` raz przy starcie poda (np. połączenie z bazą), `stop()` przy scale-down |
| `pyproject.toml` | zależności (`dependencies = [...]`), nie `requirements.txt` |
| `func.yaml` | nazwa, runtime, rejestr, zmienne środowiskowe; bez kodu |
| `tests/test_func.py` | test pytest wywołujący `handle()` |

Zmień funkcję tak, żeby zwracała JSON ze ścieżką żądania. Nadpisz `function/func.py` w całości:

```bash
cd ~/hello-fn
cat > function/func.py <<'EOF'
import json


def new():                       # wymagane: func woła new() przy starcie i dostaje instancję
    return Function()


class Function:
    async def handle(self, scope, receive, send):
        path = scope.get("path", "/")      # .get(): test z szablonu podaje pusty scope
        out = {"hello": "MemeOps", "path": path}
        await send({"type": "http.response.start", "status": 200,
                    "headers": [[b"content-type", b"application/json"]]})
        await send({"type": "http.response.body", "body": json.dumps(out).encode()})
EOF
```

`start`, `stop`, `alive` i `ready` są opcjonalne, więc tu ich nie ma. **`new()` musi zostać**: bez niej pod wpada w `CrashLoopBackOff` z błędem `cannot import name 'new'`.

Wdróż ponownie i sprawdź:

```bash
func deploy --builder=host --registry localhost:5001 --registry-insecure --namespace memeops
curl http://hello-fn.memeops.127.0.0.1.sslip.io/api/memes   # {"hello": "MemeOps", "path": "/api/memes"}
kn revision list -n memeops -s hello-fn                      # dwie rewizje
kubectl get ksvc hello-fn -n memeops -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
cd ~/memeops
```

Digest jest inny niż za pierwszym razem: nowy kod to nowy obraz i nowa rewizja. To surowe ASGI: `scope` opisuje żądanie, `send` wysyła odpowiedź w dwóch krokach (nagłówki, body), a body żądania czytasz przez `await receive()`.

```bash
kn service delete hello-fn -n memeops
```

### B. `meme-gen` z szablonu firmowego

`app/meme-gen/` powstał z `templates/python-http/`. Tu kod jest rozłożony inaczej niż w `func`: `main.py` to serwer HTTP i routing endpointów (piszesz go sam, razem z `/healthz` i portem), `memes.py` rysuje mema, `auth.py` sprawdza JWT. Obraz opisuje `Dockerfile`. Przejrzyj `main.py` (endpointy i zmienne środowiskowe w docstringu) i uruchom testy:

```bash
docker run --rm -v "$PWD/app/meme-gen:/src:ro" -w /src python:3.12-slim \
  sh -c "pip install -q pytest && python -m pytest -q -p no:cacheprovider"
```

Zbuduj obraz z dwoma tagami — wersją i SHA commita — i wypchnij:

```bash
SHA=$(git rev-parse --short HEAD)
docker build -t localhost:5001/meme-gen:1.0.0 -t localhost:5001/meme-gen:$SHA app/meme-gen
docker push localhost:5001/meme-gen:1.0.0 && docker push localhost:5001/meme-gen:$SHA
curl -s localhost:5001/v2/meme-gen/tags/list
```

W `labs/lab03-funkcja-python/meme-gen.yaml` wpisz SHA w adnotacji `memeops/git-sha`, potem:

```bash
kubectl apply -f labs/lab03-funkcja-python/meme-gen.yaml
kn service describe meme-gen -n memeops
```

Otwórz w przeglądarce VM-ki **http://meme-gen.memeops.127.0.0.1.sslip.io** i wygeneruj mema. ✅ Widzisz mema w SVG, a pod nim `/api/info` z wersją `1.0.0`.

### C. Nowa wersja i rollback

Organizator chce znak wodny konferencji:

```bash
kn service update meme-gen -n memeops --env APP_VERSION=1.1.0 --env WATERMARK="#MemeOpsConf"
kn revision list -n memeops -s meme-gen
```

Wygeneruj mema — jest znak wodny. Znak wodny okazuje się za duży: cofnij ruch do pierwszej rewizji bez budowania czegokolwiek.

```bash
kn service update meme-gen -n memeops --traffic meme-gen-00001=100
curl -s http://meme-gen.memeops.127.0.0.1.sslip.io/api/info
```

Teraz wróć do najnowszej rewizji (`--traffic @latest=100`). Jak ustalić, z jakiego commita pochodzi działająca rewizja? (`kubectl get revision … -o yaml`, adnotacje.)

### D. Pułapka: nadpisany tag

Na tym klastrze Knative **nie** zamienia tagów na digest dla `localhost:5001` (patrz `setup/platform.sh`). Co by się stało, gdyby ktoś zbudował inny kod i znów wypchnął `meme-gen:1.0.0`, a rewizja `meme-gen-00001` wystartowała po scale-to-zero? Zapisz odpowiedź — omówimy ją razem.

## SUKCES

- [ ] `curl localhost:5001/v2/meme-gen/tags/list` pokazuje `1.0.0` i tag z SHA
- [ ] w przeglądarce generujesz mema SVG, `/api/info` pokazuje wersję i rewizję
- [ ] masz co najmniej dwie rewizje `meme-gen` i umiesz przełączyć ruch między nimi jedną komendą

## Dla chętnych

- Wdróż `meme-gen` przez `func`: `func deploy` w katalogu bez `func.yaml` nie zadziała — co trzeba dodać? (porównaj `hello-fn/func.yaml`)
- `docker inspect localhost:5001/meme-gen:1.0.0 --format '{{.Config.User}}'` — dlaczego szablon firmowy ustawia `USER 10001`?

## Dogoń grupę

```bash
tools/start-lab.sh lab03            # tylko jeśli LAB 2 nie skończony (usuwa i tworzy od nowa meme-api)
```

## Gdy coś nie działa

| Objaw | Co zrobić |
|---|---|
| `func deploy`: błąd rejestru | czy jest `--registry-insecure`; `curl localhost:5001/v2/` |
| `func`: `python3 not found` | builder `host` potrzebuje Pythona 3 na VM: `sudo apt install -y python3 python3-venv` albo pomiń część A |
| nowa rewizja `hello-fn` w `CrashLoopBackOff`, w logach `cannot import name 'new'` | z `func.py` zniknęła funkcja `new()`; wklej plik z kroku A jeszcze raz i `func deploy` |
| `git rev-parse` nie działa | jesteś poza repo: `cd ~/memeops` |
