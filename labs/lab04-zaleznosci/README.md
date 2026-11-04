# lab04 — Zależności natywne: memy ze zdjęciami

> **Zgłoszenie od PO:** „SVG nie działa w komunikatorach. Chcemy prawdziwe obrazki PNG.”

**Cel:** dodajesz bibliotekę z kodem natywnym (Pillow), porównujesz dwa sposoby budowania obrazu i mierzysz, ile kosztuje to w cold starcie.

**Zasada:** każdy megabajt obrazu płacisz przy pierwszym starcie na nowym węźle.

## Kroki

| # | Co robisz |
|---|---|
| 1 | Pillow w `requirements.txt` |
| 2 | Dwa obrazy: „na szybko” i multi-stage |
| 3 | Wdrożenie i czas do Ready |
| 4 | Cold start na „nowym węźle” |
| 5 | Wnioski |

### 1. Pillow w `requirements.txt`

W `app/meme-gen/requirements.txt` odkomentuj linię `pillow==12.3.0` (usuń `# ` z początku). W edytorze albo komendą:

```bash
sed -i 's/^# pillow/pillow/' app/meme-gen/requirements.txt
cat app/meme-gen/requirements.txt        # ostatnia linia: pillow==12.3.0 (bez #)
```

Sprawdź, co by się stało bez tego kroku (obraz `1.0.0` z LAB 3 nie ma Pillow):

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

Przeczytaj oba Dockerfile. Skąd różnica rozmiaru (`python:3.12` vs `python:3.12-slim`, etapy, `--no-cache-dir`)? Dlaczego Pillow instaluje się bez kompilatora (wheele *manylinux*: paczki pip z już skompilowanym kodem C)?

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
NOWY_WEZEL=1 tools/coldstart.sh meme-gen memeops /api/memes POST '{"top":"cold","bottom":"start"}'
tools/coldstart.sh meme-gen memeops /api/memes POST '{"top":"cold","bottom":"start"}'   # obraz już w cache
```

Powtórz dla obrazu `2.0.0-full` (`kn service update meme-gen -n memeops --image localhost:5001/meme-gen:2.0.0-full`, potem oba pomiary). Uzupełnij tabelę z LAB 2:

| Pomiar | Rozmiar obrazu | Czas do Ready | Cold, bez obrazu na węźle | Cold, obraz w cache | Warm |
|---|---|---|---|---|---|
| meme-api v1 (lab02) | | — | — | | |
| meme-gen 2.0.0-full | | | | | |
| meme-gen 2.0.0 (multi-stage) | | | | | |

Różnica w kolumnie „bez obrazu na węźle” może być mała albo żadna: rejestr `localhost:5001` stoi na tej samej VM-ce, więc pobranie nawet 430 MB trwa ułamek sekundy. Koszt rozmiaru widać tu w **czasie do Ready** z kroku 3 (pierwsze uruchomienie obrazu na węźle). Na produkcji obraz idzie z zewnętrznego rejestru przez sieć na każdy nowy węzeł — tam różnica rośnie do sekund albo dziesiątek sekund.

Na koniec zostaw usługę na obrazie `2.0.0` (multi-stage).

### 5. Wnioski

Z czego składa się cold start i który składnik zależy od rozmiaru obrazu? Co jeszcze go wydłuża w Pythonie (importy przy starcie)?

## SUKCES

- [ ] `meme-gen` generuje PNG na obrazie `2.0.0`
- [ ] tabela ma pomiary dla obu obrazów, w tym cold start bez obrazu na węźle
- [ ] umiesz wskazać, w którym pomiarze widać koszt rozmiaru obrazu i dlaczego na VM-ce jest mniejszy niż na produkcji

## Dla chętnych

- Dodaj do `Dockerfile.slim` `ENV PYTHONDONTWRITEBYTECODE=1` albo prekompilację (`python -m compileall`) i zmierz, czy start procesu się zmienia (`startup_ms` w pierwszym logu: `kubectl logs -n memeops -l serving.knative.dev/service=meme-gen -c user-container | head -1`).
- `docker history localhost:5001/meme-gen:2.0.0-full` — która warstwa jest największa?

## Dogoń grupę

```bash
tools/start-lab.sh lab04            # tylko jeśli LAB 3 nie skończony (usuwa Twoje rewizje meme-api i meme-gen)
```

**Koniec dnia 1 — cliffhanger:** „Jutro keynote. Przyjdzie 500 osób naraz. Wytrzymamy?”
