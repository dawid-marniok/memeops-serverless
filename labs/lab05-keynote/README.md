# lab05 — Symulacja keynote: testy, metryki, autoskalowanie

| Dzień | Po bloku |
|---|---|
| 2 | 2.1 Testowanie, metryki i autoskalowanie |

> **Zgłoszenie od PO:** „Keynote kończy się o 10:00. Przez godzinę przed — cisza. Potem 500 osób chce mema w ciągu 5 minut. Udowodnijcie, że wytrzymamy, i powiedzcie, ile to kosztuje.”

**Cel:** testujesz funkcję (pytest i k6), obserwujesz skalowanie 0 → N → 0, stroisz autoskaler i podejmujesz decyzję o `min-scale` na czas keynote.

**Zasada:** jedna zmiana parametru na jeden przebieg testu — inaczej nie wiesz, co pomogło.

## Przed startem

Stan startowy: `meme-gen` 2.0.0 (PNG) z LAB 4, domyślne autoskalowanie.

```bash
tools/start-lab.sh lab05            # tylko jeśli LAB 4 nie skończony (usuwa Twoje rewizje meme-api i meme-gen)
```

Na początku labu prowadzący pokazuje [demo 07 „Keynote na domyślnych ustawieniach”](../../demo/07-keynote/) — to ten sam test co Twój przebieg 1, na laptopie prowadzącego.

## Kroki

| # | Co robisz |
|---|---|
| 1 | Testy funkcji przed obciążeniem |
| 2 | Przebieg 1: domyślny autoskaler |
| 3 | Przebieg 2: `target: 5` |
| 4 | Przebieg 3: Twoja zmiana |
| 5 | Decyzja na keynote |
| 6 | Zagadka galerii |

Otwórz **drugi terminal** (w oknie terminala: File → Open Tab) i uruchom w nim podgląd na cały lab. Gdy skończysz, zamknij tę kartę (×): w terminalu DaDesktop Ctrl+C nie przerywa komend.

```bash
watch -n2 'kubectl get kpa -n memeops; echo; kubectl get pods -n memeops -l serving.knative.dev/service=meme-gen'
```

Z `--monitoring`: Grafana http://localhost:3000 (`admin`/`memeops`) → dashboard **MemeOps — funkcja Knative**.

### 1. Testy funkcji

```bash
docker run --rm -v "$PWD/app/meme-gen:/src:ro" -w /src python:3.12-slim \
  sh -c "pip install -q pytest -r requirements.txt && python -m pytest -q -p no:cacheprovider"
```

✅ Wszystkie testy zielone, test PNG już nie jest pominięty (`skipped`).

### 2. Przebieg 1: domyślny autoskaler

```bash
k6 run tools/keynote.js
```

Ten sam test widziałeś w demie 07 — powtórz go u siebie, bo na VM-ce liczby będą inne i to one są Twoim punktem odniesienia. Zapisz: maks. liczbę podów, p95 czasu odpowiedzi (`http_req_duration … p(95)`), odsetek błędów (`http_req_failed`). Czerwone `thresholds … have been crossed` na końcu oznacza tylko, że test przekroczył progi z `keynote.js` (p95 < 1 s, błędy < 1%). To też jest wynik, zapisz go. Domyślny cel to 100 równoczesnych żądań na pod (`kubectl get cm config-autoscaler -n knative-serving -o yaml | grep container-concurrency-target-default`).

### 3. Przebieg 2: `target: 5`

Przeczytaj `labs/lab05-keynote/autoscaling.yaml` (każda adnotacja ma komentarz), wdroż i powtórz test:

```bash
kubectl apply -f labs/lab05-keynote/autoscaling.yaml
k6 run tools/keynote.js
```

Obserwuj w `kubectl get kpa`: `DESIRED` vs `ACTUAL`, a w Grafanie concurrency stabilną i *panic*.

### 4. Przebieg 3: Twoja zmiana

Wybierz **jedną** zmianę w `autoscaling.yaml`, przewidź wynik, wdróż, sprawdź:
- `target: "1"` (przesadnie agresywnie),
- `metric: rps` + `target: "20"`,
- `max-scale: "2"` (bezpiecznik kosztowy za ciasny),
- `k6 run -e PEAK=100 tools/keynote.js` (2,5× większy szczyt). Uwaga: na VM-ce to już przeciąża węzeł (p95 kilka-kilkanaście sekund, błędy) nawet przy `target: 5`. Dlaczego dodawanie podów nie pomaga, gdy brakuje CPU na węźle?

| Przebieg | Zmiana | Maks. podów | p95 | Błędy | Przewidywanie trafione? |
|---|---|---|---|---|---|
| 1 | domyślne | | | | — |
| 2 | target 5 | | | | |
| 3 | | | | | |

### 5. Decyzja na keynote

Zmierz cold start po scale-to-zero (`tools/coldstart.sh meme-gen memeops /api/memes POST '{"top":"x"}'`). Organizator płaci za każdy działający pod. Zaproponuj ustawienie na czas keynote (np. `min-scale` 2 od 9:45 do 10:30, potem 0) i zapisz uzasadnienie w jednym zdaniu: koszt vs pierwsze wrażenie użytkownika. Jak zmienić to o 9:45 bez ręcznej pracy? (Podpowiedź: każda zmiana to nowa rewizja — kto może ją wdrożyć o zadanej godzinie?)

### 6. Zagadka galerii

Po teście z kilkoma podami:

```bash
for i in $(seq 1 5); do curl -s http://meme-gen.memeops.127.0.0.1.sslip.io/api/memes | head -c 120; echo; done
```

Dlaczego galeria za każdym razem wygląda inaczej, a po scale-to-zero jest pusta? Co to mówi o przechowywaniu stanu w funkcji?

## SUKCES

- [ ] tabela ma trzy przebiegi z liczbą podów, p95 i błędami
- [ ] widziałeś skalowanie 0 → N → 0 (`kubectl get kpa` albo Grafana)
- [ ] masz zapisaną decyzję `min-scale` na keynote z uzasadnieniem kosztowym

## Dla chętnych

- `autoscaling.knative.dev/class: hpa.autoscaling.knative.dev` + `metric: cpu` — wymaga `serving-hpa.yaml` z wydania Knative. Czym różni się zachowanie od KPA (scale-to-zero?)
- `autoscaling.knative.dev/initial-scale: "3"` — kiedy to ma sens przy wdrożeniu nowej wersji tuż przed szczytem?

## Dogoń grupę

```bash
tools/start-lab.sh lab05
```

**Cliffhanger:** „Ktoś wrzuca memy anonimowo, a klucz leży w kodzie.”
