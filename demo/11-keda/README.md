# 11 — KEDA: skalowanie od kolejki

**Cel:** zobaczyć drugą drogę do serverless na Kubernetesie, bez Knative. KEDA skaluje zwykły Deployment od zera według długości kolejki, a nie według ruchu HTTP.

```
redis-cli RPUSH (producent) ──→ lista „memy” w Redisie ──→ generator (Deployment, 0..10 podów)
                                        ↑
                              KEDA sprawdza długość co 5 s
```

Dwa terminale: **T1** obserwuje, **T2** wykonuje.

## Przygotowanie: instalacja KEDA

```bash
helm repo add kedacore https://kedacore.github.io/charts
helm upgrade --install keda kedacore/keda --version 2.21.0 -n keda --create-namespace --wait
kubectl get pods -n keda
```

👀 Trzy pody: `keda-operator` (przełącza 0 ↔ 1), `keda-operator-metrics-apiserver` (podaje długość kolejki jako metrykę dla HPA), `keda-admission-webhooks` (sprawdza poprawność obiektów KEDA).

## Kroki

### 1. Kolejka i worker

```bash
# T2
kubectl apply -f demo/00-namespace.yaml
kubectl apply -f demo/11-keda/1-redis.yaml -f demo/11-keda/2-generator.yaml
kubectl get deploy -n demo redis generator
```

`1-redis.yaml`: Redis, w którym lista `memy` jest kolejką zadań. `2-generator.yaml`: worker — zdejmuje zadanie z listy i „generuje mema” przez 1 s. 👀 `generator` ma `0/0` replik: bez KEDA nic go nie obudzi.

### 2. ScaledObject

```bash
cat demo/11-keda/3-scaledobject.yaml
kubectl apply -f demo/11-keda/3-scaledobject.yaml
kubectl get scaledobject,hpa -n demo
```

| Pole | Znaczenie |
|---|---|
| `scaleTargetRef: generator` | co skalować |
| `minReplicaCount: 0` / `maxReplicaCount: 10` | od zera do 10 podów |
| `pollingInterval: 5` | co 5 s KEDA sprawdza kolejkę (domyślnie 30) |
| `cooldownPeriod: 20` | ile sekund po opróżnieniu kolejki zejść do 0 (domyślnie 300) |
| `triggers: redis`, `listLength: "5"` | źródło: lista `memy`; cel: 5 zadań na pod |

👀 KEDA sama utworzyła HPA `keda-hpa-generator`. Od 1 do N skaluje ten HPA, a 0 ↔ 1 przełącza `keda-operator`.

### 3. 100 zadań naraz

```bash
# T1 — zostaw włączone
kubectl get pods -n demo -l app=generator -w
```

```bash
# T2
kubectl exec -n demo deploy/redis -- sh -c 'redis-cli RPUSH memy $(seq 1 100)'
```

`RPUSH memy 1 2 … 100` dopisuje 100 zadań na koniec listy. 👀 W T1 po kilku sekundach pierwszy pod, po kilkunastu — pięć.

Ile zadań zostało (powtórz kilka razy):

```bash
kubectl exec -n demo deploy/redis -- redis-cli LLEN memy
```

Co robią workery (póki działają):

```bash
kubectl logs -n demo -l app=generator --tail=3 --prefix
```

`--prefix` dopisuje nazwę poda do każdej linii. 👀 Różne pody zdejmują różne zadania.

### 4. Powrót do zera

👀 W T1: kolejka pusta po ok. 35 s, zero podów po ok. 50 s.

## Wynik z próby

| Czas | Pody | Zadań w kolejce |
|---|---|---|
| 0 s | 0 | 100 |
| 11 s | 1 | 90 |
| 16 s | 5 | 65 |
| 32 s | 4 | 0 |
| 47 s | 0 | 0 |

Powtórka 04.11: 5 podów po 16 s, kolejka pusta po 37 s, 0 podów po 53 s.

## Co tu się stało

- `listLength: "5"` to cel: 5 zadań w kolejce na pod. Przy 100 zadaniach HPA chciałby 20 podów (sufit: 10), ale domyślnie w jednym kroku (15 s) dodaje najwyżej 4 pody albo podwaja ich liczbę. Z 1 poda wyszło 5, a zanim przyszedł następny krok, 5 workerów opróżniło kolejkę.
- `cooldownPeriod: 20` i `stabilizationWindowSeconds: 15` skracają schodzenie do zera. Domyślnie KEDA czeka 300 s, a HPA kolejne 300 s.
- KEDA ma kilkadziesiąt skalerów: Kafka, RabbitMQ, Azure Service Bus, Prometheus, cron, długość kolejki w bazie… Ten sam mechanizm działa z Azure Functions na Kubernetesie.

| | Knative Serving | KEDA |
|---|---|---|
| co skaluje | własny obiekt `Service` (rewizje, ruch) | dowolny Deployment, Job, StatefulSet |
| według czego | ruch HTTP (concurrency, RPS) | metryki źródła zdarzeń |
| cold request HTTP | activator przytrzymuje żądanie | nie dotyczy (bez dodatku HTTP żądanie przy 0 podów przepada) |
| typowe użycie | API, funkcje HTTP | workery kolejek, przetwarzanie wsadowe |

**Wniosek:** serverless to model „0 → N → 0 według zapotrzebowania”, a nie jeden produkt. Dla HTTP: Knative. Dla kolejek i strumieni: KEDA. Oba da się mieć w jednym klastrze.

## Zadanie dodatkowe (dla chętnych, ok. 15 min)

Na tych samych plikach, po kroku 4 (zero podów). Przed każdą zmianą zapisz przewidywanie: ile podów maksymalnie i po ilu sekundach będzie zero.

### A. Mniej zadań na pod

```bash
kubectl patch scaledobject generator -n demo --type=json \
  -p '[{"op":"replace","path":"/spec/triggers/0/metadata/listLength","value":"2"}]'
kubectl exec -n demo deploy/redis -- sh -c 'redis-cli RPUSH memy $(seq 1 100)'
```

Obserwuj T1 i `kubectl get hpa -n demo -w`. Ile podów chciałby HPA, a ile dostał?

### B. Wolniejszy worker

```bash
kubectl set env deploy/generator -n demo CZAS=3
kubectl exec -n demo deploy/redis -- sh -c 'redis-cli RPUSH memy $(seq 1 100)'
```

Mem generuje się teraz 3 s zamiast 1. Czy podów będzie więcej? Ile trwa opróżnienie kolejki?

### C. Pytanie: czy któryś mem przepadł?

Worker zdejmuje zadanie (`BLPOP`) i dopiero potem je wykonuje. Co się stanie z zadaniem, gdy HPA usunie poda w trakcie pracy?

<details><summary>Odpowiedzi</summary>

- **A:** 100 ÷ 2 = 50 podów, ale `maxReplicaCount: 10` to sufit, więc dostał 10. Z sufitem płacisz czasem opróżniania kolejki, a nie liczbą podów.
- **B:** podów jest zwykle więcej, bo kolejka maleje wolniej i dłużej przekracza 5 zadań na pod. Przy 10 podach i 3 s na zadanie 100 zadań zajmuje co najmniej 30 s. Do tego dochodzi start podów.
- **C:** zadanie przepada. `BLPOP` usuwa je z listy, zanim worker skończy, a `terminationGracePeriodSeconds: 2` nie czeka na koniec pracy. Skalowanie w dół musi iść w parze z potwierdzaniem zadań: kolejka z ack (RabbitMQ, Service Bus, Redis Streams z `XACK`), obsługa SIGTERM w workerze albo `ScaledJob` zamiast `ScaledObject` (jeden Job na zadanie, nikt go nie zabija w połowie).

</details>

Powrót do ustawień dema:

```bash
kubectl set env deploy/generator -n demo CZAS-        # „-” usuwa zmienną, worker wraca do 1 s
kubectl patch scaledobject generator -n demo --type=json \
  -p '[{"op":"replace","path":"/spec/triggers/0/metadata/listLength","value":"5"}]'
```

## Sprzątanie

```bash
kubectl delete -f demo/11-keda/3-scaledobject.yaml -f demo/11-keda/2-generator.yaml -f demo/11-keda/1-redis.yaml
```

Po szkoleniu, KEDA:

```bash
helm uninstall keda -n keda
kubectl delete namespace keda
```
