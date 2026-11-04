# 06 — Tryb panic

**Cel:** zobaczyć, jak autoskaler Knative reaguje na nagły skok ruchu: przechodzi w tryb panic, liczy ruch z ostatnich 6 s zamiast 60 s i dokłada pody od razu.

## Przygotowanie

Wymaga obrazu `localhost:5001/meme-gen:2.0.0`. Jeśli skończyłeś LAB 4, masz go w rejestrze. W przeciwnym razie zbuduje go `tools/start-lab.sh lab05` (usuwa Twoje rewizje meme-api i meme-gen w `memeops`).

To osobna usługa `panika` w namespace `demo`: nie zmienia `meme-gen` z labów i nie zdradza ustawień z LAB 5. Panic zobaczysz potem sam w LAB 5 (`kubectl get kpa`, Grafana).

```bash
kubectl apply -f demo/00-namespace.yaml
kubectl apply -f demo/06-panic/panika.yaml
kubectl wait ksvc/panika -n demo --for=condition=Ready
```

Usługa `panika` ma cel 10 równoczesnych żądań na pod. Pozostałe ustawienia panic są domyślne, ale wypisane jawnie w YAML-u.

## Kroki

```bash
# terminal 1: ile podów chce autoskaler i ile jest
kubectl get kpa -n demo panika-00001 -w
```

```bash
# terminal 2
k6 run demo/06-panic/skok.js
```

`skok.js` to scenariusz k6 (generator ruchu): 20 s jeden użytkownik, potem w 1 s skok do 40 równoczesnych użytkowników na 40 s. Każdy w pętli tworzy mema PNG (`POST /api/memes`).

👀 W terminalu 1 `DESIREDSCALE` skacze z 1 do 6 w kilka sekund, `ACTUALSCALE` goni.

Po teście:

```bash
kubectl logs -n knative-serving deploy/autoscaler --since=5m | grep panika | grep -i panick
```

Logi autoskalera z ostatnich 5 min → tylko linie o usłudze `panika` → tylko te o panice. 👀 `PANICKING.` sekundę po skoku i `Un-panicking.` ok. minutę później.

## Wynik z próby

| Czas | KPA (chce / jest) | Co się dzieje |
|---|---|---|
| 0–20 s | 1 / 1 | spokój |
| +1 s po skoku | 3 / 1 | log autoskalera: `PANICKING.` |
| +4 s | 6 / 5 | |
| +7 s | 6 / 6 | 40 użytkowników obsłużonych |
| +62 s | | log: `Un-panicking.`, autoskaler wraca do okna 60 s |

k6: 8481 żądań, 0% błędów, p95 500 ms.

## Co tu się stało

- Autoskaler liczy średnią concurrency w dwóch oknach: **stable window** (60 s) i **panic window** (10% z 60 s = 6 s).
- Gdy w oknie 6 s ruch przekracza **2×** to, co obsłużą obecne pody (`panic-threshold-percentage: 200`), autoskaler przechodzi w panic: skaluje według okna 6 s i **nie zmniejsza** liczby podów, dopóki panic trwa.
- Panic kończy się, gdy przez całe stable window (60 s) nie ma powodu do paniki. Dopiero wtedy pody mogą schodzić.

**Pułapka z próby:** pierwsza wersja miała limit pamięci 256 Mi i większe memy. Przy 60 równoczesnych żądaniach pody padały z `OOMKilled`, a 99% żądań kończyło się błędem. Autoskaler dokładał pody, ale każdy nowy też padał. Szybkie skalowanie nie pomoże, jeśli jeden pod nie wytrzymuje swojego udziału w ruchu. Najpierw zmierz pamięć poda pod obciążeniem, potem ustaw `target`.

## Sprzątanie

```bash
kubectl delete -f demo/06-panic/panika.yaml
```
