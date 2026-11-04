# 10 — Nieudany rollout

**Cel:** zobaczyć, co się dzieje, gdy nowa wersja w ogóle nie startuje, i przejść kolejność diagnozy: usługa → rewizja → pod → logi.

`Dzień 2 · blok 2.4`

## Kroki

### 1. Działająca wersja

```bash
kubectl apply -f demo/00-namespace.yaml
kubectl apply -f demo/09-nieudany-rollout/v1.yaml
kubectl wait ksvc/rollout -n demo --for=condition=Ready
curl -s http://rollout.demo.127.0.0.1.sslip.io/ | tail -1
```

W osobnym terminalu puść ciągły ruch, żeby widzieć, czy użytkownicy coś zauważą:

```bash
while true; do curl -s http://rollout.demo.127.0.0.1.sslip.io/ | tail -1; sleep 2; done
```

### 2. „Drobna zmiana” przed weekendem

```bash
diff demo/09-nieudany-rollout/v1.yaml demo/09-nieudany-rollout/v2-zla-komenda.yaml
kubectl apply -f demo/09-nieudany-rollout/v2-zla-komenda.yaml
```

### 3. Diagnoza od góry

```bash
kubectl get ksvc rollout -n demo                     # 1. usługa: READY, LATESTCREATED vs LATESTREADY
kubectl get revision -n demo -l serving.knative.dev/service=rollout     # 2. rewizja: która nie jest gotowa i dlaczego
kubectl get revision rollout-v2 -n demo \
  -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.reason}: {.message}{"\n"}{end}'
kubectl get pods -n demo -l serving.knative.dev/revision=rollout-v2     # 3. pod
kubectl logs -n demo -l serving.knative.dev/revision=rollout-v2 -c user-container --tail=5   # 4. logi
```

### 4. Naprawa

```bash
kubectl apply -f demo/09-nieudany-rollout/v3-naprawa.yaml
kubectl wait ksvc/rollout -n demo --for=condition=Ready
```

## Wynik z próby

```
NAME      LATESTCREATED   LATESTREADY   READY   REASON
rollout   rollout-v2      rollout-v1    False   RevisionFailed

rollout-v2   False   ExitCode2
Ready=False ExitCode2: Container failed with: python: can't open file '/app/app.py': [Errno 2] No such file or directory
ResourcesAvailable=False ProgressDeadlineExceeded: ReplicaSet "rollout-v2-deployment-…" has timed out progressing.
```

- Rewizja v2 uznana za nieudaną po **46 s** (`progress-deadline: 45s`, domyślnie 600 s).
- Pętla `curl` przez cały czas dostawała odpowiedzi z **`rollout-v1`**: użytkownicy niczego nie zauważyli.
- Po naprawie: `LATESTCREATED = LATESTREADY = rollout-v3`, odpowiedzi z v3.

## Co tu się stało

- Knative przełącza ruch na nową rewizję dopiero, gdy jest gotowa. Nieudana rewizja nie zabiera ruchu, więc stara wersja działa dalej.
- **`latestCreatedRevisionName` ≠ `latestReadyRevisionName`** to pierwszy sygnał, że ostatnie wdrożenie się nie udało. Warto go mieć w alertach.
- Przyczyna jest wprost w statusie rewizji (`Container failed with: …`). Nie trzeba zgadywać ani od razu czytać logów.
- Naprawa to **nowa rewizja**, nie edycja starej.
- `progress-deadline` skrócony do 45 s tylko na demo. Domyślne 10 min to dużo, gdy pipeline czeka na wynik wdrożenia.

To ta sama kolejność diagnozy, której użyjesz w LAB 8. Awarie w labie są inne.

## Sprzątanie

```bash
kubectl delete ksvc rollout -n demo
```
