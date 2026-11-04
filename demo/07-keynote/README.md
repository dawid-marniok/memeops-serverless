# 07 — Keynote na domyślnych ustawieniach

**Cel:** zobaczyć, jak `meme-gen` zachowuje się pod obciążeniem z keynote'a, **zanim** dostroisz autoskalowanie. To punkt wyjścia do LAB 5.

## Przygotowanie

Demo działa na stanie startowym LAB 5: `meme-gen` 2.0.0 w namespace `memeops`, domyślne autoskalowanie. Jeśli skończyłeś LAB 4, masz go już u siebie i nic nie uruchamiasz. W przeciwnym razie:

```bash
tools/start-lab.sh lab05              # usuwa i tworzy od nowa meme-api i meme-gen (tracisz własne rewizje)
```

Ten test powtarzasz jako przebieg 1 w [LAB 5](../../labs/lab05-keynote/).

Grafana wymaga platformy z `--monitoring`.

Grafana: http://localhost:3000 (`admin` / `memeops`) → dashboard **MemeOps — funkcja Knative**, usługa `meme-gen`.

## Kroki

```bash
# terminal 1
kubectl get pods -n memeops -l serving.knative.dev/service=meme-gen -w
```

```bash
# terminal 2
k6 run -e PEAK=100 tools/keynote.js
```

`keynote.js` to scenariusz k6: 20 s pojedyncze żądania → w 10 s wzrost do `PEAK` nowych żądań na sekundę → 60 s szczytu → 20 s spadku. `-e PEAK=100` nadpisuje domyślne 40. Próg testu: p95 < 1 s i mniej niż 1% błędów.

Patrz na trzy rzeczy: liczba podów (terminal 1), p95 na dashboardzie, podsumowanie k6.

## Wynik z próby

| Co | Wynik |
|---|---|
| liczba podów przez cały test | **1** |
| żądania | 7514, błędów 0% |
| p95 | 692 ms |
| najdłuższe żądanie | 15,4 s (pierwsze, przy zerze podów) |

## Co tu się stało

- Domyślny cel to 100 równoczesnych żądań na pod. Jeden pod „mieścił” cały ruch w tej definicji, więc autoskaler nie miał powodu dodawać podów.
- Użytkownicy i tak czekali: p95 prawie 0,7 s, a pierwszy cold start ponad 15 s.
- Na VM-ce (mniej CPU niż laptop) liczby będą gorsze, a próg k6 `p(95)<1000` może nie przejść.

**Pytanie do LAB 5:** które ustawienia zmienić, żeby przy keynote powstało więcej podów, zanim użytkownicy zaczną czekać? I czy na czas keynote warto mieć pod rozgrzany zawczasu?

## Sprzątanie

Nic: LAB 5 zaczyna z tego stanu.
