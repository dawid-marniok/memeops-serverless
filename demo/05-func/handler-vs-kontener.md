# Handler a zwykły kontener

Ściąga do dema 05, bloku 1.5 i LAB 3. Tłumaczy, czym jest **handler**, co robi `func create` i czym funkcja z `func` różni się od zwykłego kontenera.

Ta sama treść w wersji graficznej: [`handler-vs-kontener.html`](handler-vs-kontener.html). Otwórz plik w przeglądarce.

## W jednym zdaniu

> **Handler** to funkcja, którą platforma wywołuje przy każdym żądaniu. Ty piszesz tylko to, co ma się stać z żądaniem. Serwer HTTP, port, health probe'y i obraz kontenera daje szablon.

Analogia: handler to urządzenie, które podłączasz do gniazdka. Gniazdko (serwer, port, kontener) dostarcza platforma. Ty decydujesz tylko, co urządzenie robi, gdy popłynie prąd, czyli gdy przyjdzie żądanie.

## Dwie drogi do tej samej usługi

### Droga 1: zwykły kontener (LAB 3, krok B: szablon firmowy)

Piszesz **całą aplikację**: serwer, obsługę portu, healthcheck, logi i Dockerfile. Fragment `templates/python-http/main.py`:

```python
def handle(method, path, body):                 # ← logika biznesowa
    return 200, {"hello": "MemeOps", "path": path}

class Handler(BaseHTTPRequestHandler):           # ← serwer HTTP: piszesz sam
    def _serve(self):
        if self.path == "/healthz":              # ← healthcheck: piszesz sam
            ...
        status, out = handle(self.command, self.path, body)
        ...                                      # ← nagłówki, JSON, logi: piszesz sam

if __name__ == "__main__":                       # ← start serwera i port: piszesz sam
    ThreadingHTTPServer(("", int(os.environ.get("PORT", "8080"))), Handler).serve_forever()
```

Do tego `Dockerfile`:

```dockerfile
FROM python:3.12-slim
COPY *.py ./
USER 10001
CMD ["python", "main.py"]
```

Budujesz sam: `docker build` → `docker push` → `kubectl apply -f service.yaml`.

### Droga 2: funkcja z `func` (demo 05 i LAB 3, krok A)

`func create -l python hello-fn` generuje projekt. Piszesz **tylko handler**. Oto `function/func.py` w wersji wygenerowanej przez `func` v0.50 (Knative 1.23), skrócony:

```python
def new():                                      # platforma woła to raz, przy starcie
    return Function()

class Function:
    async def handle(self, scope, receive, send):   # ← TY: reakcja na każde żądanie
        await send({"type": "http.response.start", "status": 200,
                    "headers": [[b"content-type", b"text/plain"]]})
        await send({"type": "http.response.body", "body": b"OK"})

    def start(self, cfg): ...    # opcjonalnie: start instancji (cfg = zmienne środowiskowe)
    def stop(self): ...          # opcjonalnie: sprzątanie przy scale-down
    def alive(self): ...         # opcjonalnie: /health/liveness
    def ready(self): ...         # opcjonalnie: /health/readiness
```

Nie ma tu `if __name__ == "__main__"`, portu, serwera ani Dockerfile. `func deploy` sam buduje obraz (`--builder=host`, `pack` albo `s2i`), owija handler serwerem ASGI z szablonu, wypycha obraz do rejestru i tworzy Knative Service.

## Różnice w tabeli

| | Zwykły kontener | Funkcja z `func` |
|---|---|---|
| Co piszesz | całą aplikację | jedną metodę `handle()` |
| Serwer HTTP i port | ty (`PORT` z env) | szablon |
| Healthcheck | ty (`/healthz`) | szablon (`/health/liveness`, `/health/readiness`), opcjonalnie twoje `alive()`/`ready()` |
| Start i zamknięcie | ty, jeśli w ogóle | gotowe haki `start(cfg)` i `stop()` |
| Dockerfile | ty | nie ma, obraz buduje builder |
| Budowanie | `docker build` + `docker push` | `func build` / `func deploy` |
| Konfiguracja projektu | `Dockerfile` + `service.yaml` | `func.yaml` |
| Kontrola nad obrazem (baza, użytkownik, warstwy) | pełna | taka, jaką daje builder |
| Testy | piszesz sam | szablon daje `tests/test_func.py` |
| **Co ląduje w klastrze** | **Knative Service (`ksvc`)** | **Knative Service (`ksvc`)** |

Ostatni wiersz jest najważniejszy: **handler nie znaczy „bez kontenera”**. Obraz powstaje w obu przypadkach. Różnica polega na tym, kto pisze kod serwera i kto buduje obraz.

## Co robią komendy `func`

| Komenda | Co robi | Dotyka klastra? |
|---|---|---|
| `func create -l python hello-fn` | generuje katalog z szablonu: `func.yaml`, `function/func.py`, `pyproject.toml`, `tests/` | nie (szablony są wbudowane w binarkę) |
| `func build` | buduje obraz kontenera z twojego handlera i szablonu | nie |
| `func deploy` | build → push do rejestru → utworzenie albo aktualizacja `ksvc`, obraz wskazany **po digeście** (`@sha256:…`) | tak |
| `func create --repository <git-url>` | to samo, ale z **własnego** repozytorium szablonów, np. firmowego | nie |

Przydatne opcje `func create`: `-l` to język (`python`, `go`, `node`, `typescript`, `rust`, `quarkus`, `springboot`), `-t` to szablon (`http` domyślnie albo `cloudevents`).

## Wyzwalacz → platforma → handler

Handler **nie decyduje, kiedy** aplikacja startuje. Mówi tylko, **co** zrobić ze zdarzeniem. To trzy różne role:

| Rola | Pytanie | Kto za to odpowiada |
|---|---|---|
| **Wyzwalacz** | *kiedy* coś ma się stać? | zdarzenie z zewnątrz: żądanie HTTP, wiadomość z kolejki, cron |
| **Platforma** | *kto* to odbiera i budzi pod? | Knative (activator, gdy jest 0 podów), a w kontenerze serwer z szablonu nasłuchujący na porcie |
| **Handler** | *co* zrobić z tym zdarzeniem? | ty: `handle()` |

```
zdarzenie ──▶ Knative odbiera ──▶ start poda ──▶ serwer z szablonu ──▶ handle() ──▶ odpowiedź
              (activator, gdy     (cold start)   (nasłuchuje na
               0 podów)                           porcie)
```

Przy cold starcie z LAB 2 pierwsze żądanie odebrał **activator**, a nie handler. Handler dostał je dopiero, gdy pod już działał.

Analogia: wyzwalacz to dzwonek do drzwi, platforma to ktoś, kto słyszy dzwonek i otwiera, a handler to rozmowa z gościem w progu.

### Przykłady wyzwalaczy

| Wyzwalacz | Przykład w MemeOps | Szablon `func` | Czego wymaga w klastrze |
|---|---|---|---|
| **Żądanie HTTP** | użytkownik klika „Generuj mema” → `POST /api/memes` | `-t http` | Knative Serving |
| **Webhook** | GitHub po pushu wysyła POST → funkcja odświeża szablony memów | `-t http` | Knative Serving |
| **Cron** | co noc o 3:00 czyszczenie starej galerii | `-t cloudevents` | Eventing: `PingSource` |
| **Wiadomość z kolejki** | Kafka: „nowe zdjęcie wgrane” → funkcja robi miniaturę | `-t cloudevents` | Eventing: `KafkaSource` |
| **Zdarzenie w klastrze** | ktoś usunął pod → powiadomienie na Slacka | `-t cloudevents` | Eventing: `ApiServerSource` |

Platforma z `setup/platform.sh` ma tylko **Knative Serving**, więc w labach są wyłącznie wyzwalacze HTTP. Pozostałe wymagają osobnego komponentu, **Knative Eventing**. Dokłada go demo 04 ([`../04-eventing/`](../04-eventing/)): `PingSource` → Broker → Trigger budzi funkcję co minutę.

### Ten sam handler, inne wejście

```python
# -t http: dostajesz surowe żądanie
async def handle(self, scope, receive, send):
    path = scope["path"]          # np. /api/memes

# -t cloudevents: dostajesz gotowe zdarzenie
async def handle(self, scope, receive, send):
    event = scope["event"]        # np. type="photo.uploaded", data={...}
```

O tym, **kto i kiedy** zawoła handler, decyduje konfiguracja w klastrze (Source, Broker, Trigger), a nie kod funkcji.

## Słowo „handler” na innych platformach

Ten sam wzorzec, inna sygnatura:

| Platforma | Handler w Pythonie |
|---|---|
| Knative Functions (`func`) | `async def handle(self, scope, receive, send)` |
| OpenFaaS (`python3-http`) | `def handle(event, context)` |
| AWS Lambda | `def lambda_handler(event, context)` |
| Szablon firmowy MemeOps | `def handle(method, path, body)`, ale serwer jest w tym samym pliku |

## Kiedy co wybrać

**`func` (handler)**, gdy:
- chcesz szybko zacząć i nie interesuje cię, jak zbudowany jest obraz
- zespół nie zna Dockera albo nie chce go utrzymywać
- funkcja jest mała i robi jedną rzecz

**Zwykły kontener albo szablon firmowy**, gdy:
- firma ma zasady dotyczące obrazu: konkretna baza, użytkownik bez roota, skanowanie
- potrzebujesz zależności natywnych (np. Pillow, biblioteki C) i kontroli nad tym, jak się instalują
- masz już aplikację w kontenerze i nie chcesz jej przepisywać

Złoty środek: `func create --repository` z **firmowym** repozytorium szablonów. Programista pisze tylko handler, a zasady firmy siedzą w szablonie.

## Sprawdź sam

```bash
cd ~ && func create -l python hello-fn && cd hello-fn
ls -R                        # struktura projektu
cat func.yaml                # metadane: nazwa, runtime
cat function/func.py         # twój handler
cd ~ && rm -rf hello-fn      # sprzątanie (nic nie trafiło do klastra)
```

Wdrożenie i podgląd obrazu po digeście robisz w [LAB 3, krok A](../../labs/lab03-funkcja-python/README.md).
