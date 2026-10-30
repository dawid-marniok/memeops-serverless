# lab04 — Zależności natywne: memy ze zdjęciami

| Dzień | Czas | Po bloku |
|---|---|---|
| 1 | 40 min | 1.6 Zależności i rozszerzenia natywne |

> **Zgłoszenie od PO:** „SVG nie działa w komunikatorach. Chcemy prawdziwe obrazki PNG.”

**Cel:** dodajesz bibliotekę z kodem natywnym (Pillow), porównujesz dwa sposoby budowania obrazu i mierzysz, ile kosztuje to w cold starcie.

**Zasada:** każdy megabajt obrazu płacisz przy pierwszym starcie na nowym węźle.

## Kroki

| # | Co robisz | Czas |
|---|---|---|
| 1 | Pillow w `requirements.txt` | 5 min |
| 2 | Dwa obrazy: „na szybko” i multi-stage | 10 min |
| 3 | Wdrożenie i czas do Ready | 10 min |
| 4 | Cold start na „nowym węźle” | 10 min |
| 5 | Wnioski | 5 min |

### 1. Pillow w `requirements.txt`

W `app/meme-gen/requirements.txt` odkomentuj linię `pillow==12.3.0`. Sprawdź, co by się stało bez tego kroku:

```bash
docker run --rm -e MEME_FORMAT=png localhost:5001/meme-gen:1.0.0
```

✅ Funkcja kończy się od razu z logiem `fatal … Pillow nie jest zainstalowany`. Dobrze: lepiej paść przy starcie niż przy pierwszym użytkowniku.

### 2. Dwa obrazy

```bash
time docker build -f app/meme-gen/Dockerfile.full -t localhost:5001/meme-gen:2.0.0-full app/meme-gen
time docker build -f app/meme-gen/Dockerfile.slim -t localhost:5001/meme-gen:2.0.0 app/meme-gen
docker push localhost:5001/meme-gen:2.0.0-full && docker push localhost:5001/meme-gen:2.0.0
docker images localhost:5001/meme-gen
```

Przeczytaj oba Dockerfile. Skąd różnica rozmiaru (`python:3.12` vs `python:3.12-slim`, etapy, `--no-cache-dir`)? Dlaczego Pillow instaluje się bez kompilatora (koła *manylinux*)?

### 3. Wdrożenie i czas do Ready

```bash
time kn service update meme-gen -n memeops --image localhost:5001/meme-gen:2.0.0-full \
  --env MEME_FORMAT=png --env APP_VERSION=2.0.0-full --limit memory=256Mi
time kn service update meme-gen -n memeops --image localhost:5001/meme-gen:2.0.0 \
  --env APP_VERSION=2.0.0
```

Wygeneruj mema w przeglądarce — teraz to PNG.

### 4. Cold start na „nowym węźle”

Nowy węzeł nie ma obrazu w cache. `NOWY_WEZEL=1` symuluje to: gdy usługa zejdzie do zera, skrypt usuwa obraz z węzła kind (`crictl rmi`), więc pierwsze żądanie czeka też na pobranie obrazu.

```bash
NOWY_WEZEL=1 tools/coldstart.sh meme-gen memeops /api/memes POST '{"top":"zimny","bottom":"start"}'
tools/coldstart.sh meme-gen memeops /api/memes POST '{"top":"zimny","bottom":"start"}'   # obraz już w cache
```

Powtórz dla obrazu `2.0.0-full` (`kn service update meme-gen -n memeops --image localhost:5001/meme-gen:2.0.0-full`, potem oba pomiary). Uzupełnij tabelę z LAB 2:

| Pomiar | Rozmiar obrazu | Czas do Ready | Zimny, bez obrazu na węźle | Zimny, obraz w cache | Ciepły |
|---|---|---|---|---|---|
| meme-api v1 (lab02) | | — | — | | |
| meme-gen 2.0.0-full | | | | | |
| meme-gen 2.0.0 (multi-stage) | | | | | |

Na koniec zostaw usługę na obrazie `2.0.0` (multi-stage).

### 5. Wnioski

Z czego składa się cold start i który składnik zależy od rozmiaru obrazu? Co jeszcze go wydłuża w Pythonie (importy przy starcie)?

## SUKCES

- [ ] `meme-gen` generuje PNG na obrazie `2.0.0`
- [ ] tabela ma pomiary dla obu obrazów, w tym zimny start bez obrazu na węźle
- [ ] umiesz wskazać, ile cold startu „zjada” pobieranie obrazu

## Dla chętnych

- Dodaj do `Dockerfile.slim` `ENV PYTHONDONTWRITEBYTECODE=1` albo prekompilację (`python -m compileall`) i zmierz, czy start procesu się zmienia (`startup_ms` w pierwszym logu: `kubectl logs -n memeops -l serving.knative.dev/service=meme-gen -c user-container | head -1`).
- `docker history localhost:5001/meme-gen:2.0.0-full` — która warstwa jest największa?

## Dogoń grupę

```bash
tools/dogon.sh lab04
```

**Koniec dnia 1 — cliffhanger:** „Jutro keynote. Przyjdzie 500 osób naraz. Wytrzymamy?”
