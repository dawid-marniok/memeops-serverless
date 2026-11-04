# 11 — KEDA: skalowanie od kolejki

**Cel:** zobaczyć drugą drogę do serverless na Kubernetesie, bez Knative. KEDA skaluje zwykły Deployment od zera według długości kolejki, a nie według ruchu HTTP.

`Dzień 2 · blok 2.5`

```
redis-cli RPUSH (producent) ──→ lista „memy” w Redisie ──→ generator (Deployment, 0..10 podów)
                                        ↑
                              KEDA sprawdza długość co 5 s
```

## Przygotowanie

```bash
demo/11-keda/prepare.sh        # KEDA 2.21 (Helm) + Redis + Deployment generator z 0 replik + ScaledObject, ok. 1 min
```

## Kroki

### 1. Co powstało

```bash
kubectl get scaledobject,hpa,deploy -n demo
```

`generator` ma 0 replik. KEDA utworzyła HPA (`keda-hpa-generator`) i sama przełącza Deployment między 0 a 1. Od 1 do N skaluje już zwykły HPA.

### 2. 100 zadań naraz

```bash
# terminal 1
kubectl get pods -n demo -l app=generator -w
```

```bash
# terminal 2
kubectl exec -n demo deploy/redis -- sh -c 'redis-cli RPUSH memy $(seq 1 100)'
watch -n 2 "kubectl exec -n demo deploy/redis -- redis-cli LLEN memy"
```

```bash
kubectl logs -n demo -l app=generator --tail=3 --prefix
```

## Wynik z próby

| Czas | Pody | Zadań w kolejce |
|---|---|---|
| 0 s | 0 | 100 |
| 11 s | 1 | 90 |
| 16 s | 5 | 65 |
| 32 s | 4 | 0 |
| 47 s | 0 | 0 |

## Co tu się stało

- `listLength: "5"` to cel: 5 zadań w kolejce na pod. Przy 100 zadaniach HPA chciałby 20 podów, ale kolejka znikała szybciej, niż pody startowały, więc skończyło się na 5.
- `cooldownPeriod: 20` i `stabilizationWindowSeconds: 15` skracają schodzenie do zera. Domyślnie KEDA czeka 300 s, a HPA kolejne 300 s.
- KEDA ma kilkadziesiąt skalerów: Kafka, RabbitMQ, Azure Service Bus, Prometheus, cron, długość kolejki w bazie… Ten sam mechanizm działa z Azure Functions na Kubernetesie.

| | Knative Serving | KEDA |
|---|---|---|
| co skaluje | własny obiekt `Service` (rewizje, ruch) | dowolny Deployment, Job, StatefulSet |
| według czego | ruch HTTP (concurrency, RPS) | metryki źródła zdarzeń |
| cold request HTTP | activator przytrzymuje żądanie | nie dotyczy (bez dodatku HTTP żądanie przy 0 podów przepada) |
| typowe użycie | API, funkcje HTTP | workery kolejek, przetwarzanie wsadowe |

**Wniosek:** serverless to model „0 → N → 0 według zapotrzebowania”, a nie jeden produkt. Dla HTTP: Knative. Dla kolejek i strumieni: KEDA. Oba da się mieć w jednym klastrze.

## Sprzątanie

```bash
demo/11-keda/prepare.sh --delete
```
