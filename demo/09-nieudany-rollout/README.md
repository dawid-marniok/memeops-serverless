# 09 — Nieudany rollout

**Cel:** zobaczyć, co się dzieje, gdy nowa wersja w ogóle nie startuje, i przejść kolejność diagnozy: usługa → rewizje → status rewizji → pod → logi.

`Dzień 2 · blok 2.4`

## Przygotowanie (kilka minut przed demem)

```bash
kubectl apply -f demo/00-namespace.yaml
kubectl apply -f demo/09-nieudany-rollout/v1.yaml
```

## Kroki

### 1. Działająca wersja

```bash
curl -s http://rollout.demo.127.0.0.1.sslip.io/ | tail -1
```

👀 `[v1 · rollout-v1 · …]` — odpowiada rewizja `rollout-v1`. Tę samą komendę powtarzaj w kolejnych krokach: tak widzi to użytkownik.

### 2. „Drobna zmiana” przed weekendem

```bash
diff demo/09-nieudany-rollout/v1.yaml demo/09-nieudany-rollout/v2-zla-komenda.yaml
kubectl apply -f demo/09-nieudany-rollout/v2-zla-komenda.yaml
```

`diff` pokazuje różnice: nowy obraz, nazwa rewizji `rollout-v2` i „uporządkowana” komenda startowa `python app.py`. W obrazie jest `main.py`.

Odczekaj ok. 45 s (`progress-deadline` skrócony na demo) i sprawdź, co widzi użytkownik:

```bash
curl -s http://rollout.demo.127.0.0.1.sslip.io/ | tail -1
```

👀 Dalej `rollout-v1`. Użytkownik niczego nie zauważył.

### 3. Diagnoza od góry

```bash
kubectl get ksvc rollout -n demo
```

👀 **1. Usługa:** `LATESTCREATED rollout-v2`, `LATESTREADY rollout-v1`, `READY False`, `RevisionFailed`. Ostatnie wdrożenie się nie udało.

```bash
kn revision list -n demo -s rollout
```

👀 **2. Rewizje:** `rollout-v2` ma `READY False` i powód `ExitCode2 : Container failed with: …`. Ruch (100%) jest na `rollout-v1`.

```bash
kubectl describe revision rollout-v2 -n demo
```

👀 **3. Status rewizji**, sekcja `Conditions`: `Message: Container failed with: python: can't open file '/app/app.py'`. To jest przyczyna — zanim otworzysz logi.

```bash
kubectl get pods -n demo -l serving.knative.dev/revision=rollout-v2
kubectl logs -n demo -l serving.knative.dev/revision=rollout-v2 -c user-container --tail=5
```

👀 **4. Pod:** `Error`, rosnące `RESTARTS`. **5. Logi:** ten sam komunikat. `-l` wybiera pody po etykiecie rewizji, `-c user-container` — tylko Twój kontener, bez `queue-proxy`.

### 4. Naprawa

```bash
kubectl apply -f demo/09-nieudany-rollout/v3-naprawa.yaml
kubectl wait ksvc/rollout -n demo --for=condition=Ready
curl -s http://rollout.demo.127.0.0.1.sslip.io/ | tail -1
kubectl get ksvc rollout -n demo
```

`kubectl wait` czeka, aż usługa będzie gotowa. 👀 Odpowiada `rollout-v3`, `LATESTCREATED = LATESTREADY = rollout-v3`.

## Wynik z próby

- Rewizja v2 uznana za nieudaną po ok. **46 s** (`progress-deadline: 45s`, domyślnie 600 s).
- Przez cały czas odpowiadała **`rollout-v1`**: użytkownicy niczego nie zauważyli.
- Po naprawie: `LATESTCREATED = LATESTREADY = rollout-v3`.

## Co tu się stało

- Knative przełącza ruch na nową rewizję dopiero, gdy jest gotowa. Nieudana rewizja nie zabiera ruchu.
- **`latestCreatedRevisionName` ≠ `latestReadyRevisionName`** to pierwszy sygnał, że wdrożenie się nie udało. Warto go mieć w alertach.
- Przyczyna jest wprost w statusie rewizji. Nie trzeba zgadywać ani od razu czytać logów.
- Naprawa to **nowa rewizja**, nie edycja starej.

To ta sama kolejność diagnozy, której użyjesz w LAB 8. Awarie w labie są inne.

## Sprzątanie

```bash
kubectl delete ksvc rollout -n demo
```
