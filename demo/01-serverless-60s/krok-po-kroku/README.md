# Demo 01 krok po kroku: Knative Service na plikach YAML

Rozszerzenie dema 01 do samodzielnej powtórki po LAB 2 albo po szkoleniu. To samo, co robisz w LAB 2 przez `kn`, tutaj zapisane w YAML-u: pierwsze wdrożenie, scale-to-zero, canary 80/20, przełączenie, rollback. Do tego ściąga ze wszystkimi ważniejszymi opcjami Knative Service.

Wymaga platformy z `setup/platform.sh` (`setup/check.sh` → 13/13) i obrazów `localhost:5001/meme-api:v1` oraz `v2` (buduje je `platform.sh`). Komendy uruchamiasz z katalogu repo. Wyniki poniżej pochodzą z próby 2026-11-04 na klastrze `memeops` (Knative 1.23).

| Plik | Co robi | Nowa rewizja? |
|---|---|---|
| `00-przygotowanie.yaml` | ServiceAccount, ConfigMap i Secret dla zakomentowanych opcji z `01` | — |
| `01-hello-v1.yaml` | usługa `hello`, 100% ruchu do `hello-v1`. **Zarazem ściąga:** zakomentowane są w nim wszystkie ważniejsze opcje Knative Service | tak: `hello-v1` |
| `02-hello-v2-canary.yaml` | obraz `v2`, ruch 80% v1 / 20% v2, tag `kandydat` | tak: `hello-v2` |
| `03-hello-v2-pelny.yaml` | 100% do najnowszej rewizji, v1 zostaje pod tagiem `poprzednia` | **nie**, zmienia się tylko ruch |

```bash
K=demo/01-serverless-60s/krok-po-kroku
U=http://hello.demo.127.0.0.1.sslip.io
kubectl apply -f demo/00-namespace.yaml -f $K/00-przygotowanie.yaml
```

Usługi mają `timeoutSeconds: 15`, jak wszystkie dema. Knative daje podowi tyle samo czasu na wyłączenie, więc pody znikają po kilkunastu sekundach, a nie po 5 minutach.

## Co można ustawić w Knative Service

Przeczytaj `01-hello-v1.yaml` od góry do dołu. Opcje są pogrupowane w komentarzach:

| Grupa | Gdzie w pliku | Przykłady |
|---|---|---|
| Widoczność i wdrażanie | `metadata` usługi | tylko wewnątrz klastra (`visibility: cluster-local`), stopniowe przejmowanie ruchu (`rollout-duration`) |
| Ile podów | adnotacje w `spec.template.metadata` | `min-scale`, `max-scale`, `initial-scale`, `activation-scale`, `scale-down-delay` |
| Według czego skalować | adnotacje | klasa KPA/HPA, metryka `concurrency`/`rps`, `target` |
| Jak szybko reagować | adnotacje | `window`, tryb panic, `target-burst-capacity` |
| Sidecar queue-proxy | adnotacje | zasoby queue-proxy, `progress-deadline` |
| Żądania i timeouty | `spec.template.spec` | `containerConcurrency`, `timeoutSeconds`, `responseStartTimeoutSeconds` |
| Tożsamość | `spec.template.spec` | `serviceAccountName`, `imagePullSecrets` |
| Kontener | `containers` | `command`/`args`, port `h2c` dla gRPC, `env`, `envFrom`, probe'y, zasoby, `securityContext`, wolumeny |
| Wyłączone domyślnie | koniec `spec.template.spec` | `nodeSelector`, `tolerations`, `affinity`, `runtimeClassName`, `initContainers`, PVC: wymagają flagi w `config-features` |
| Ruch | `spec.traffic` | szczegóły w plikach 02 i 03 |

**Jak ćwiczyć:** odkomentuj wybraną opcję, **zmień nazwę rewizji** (np. `hello-v1` → `hello-v1b`) i zrób `kubectl apply -f $K/01-hello-v1.yaml`. Bez zmiany nazwy webhook odrzuci zmianę szablonu.

Co sprawdziliśmy w próbie:
- Wszystkie opcje spoza sekcji „wyłączone domyślnie” odkomentowane naraz dają działającą rewizję. Pod startuje z ServiceAccountem `meme-api`, ma system plików tylko do odczytu, pliki z ConfigMap i Secret są podmontowane w `/etc/meme` i `/etc/sekrety`, a zapis działa tylko w `/tmp`. Usługa dostaje adres `http://hello.demo.svc.cluster.local` (efekt `cluster-local`), więc `curl $U` z laptopa już nie zadziała.
- Z `rollout-duration: 120s` nowa rewizja przejmuje ruch stopniowo (w `kn revision list` widać np. 98%), a `kubectl wait --for=condition=Ready` czeka, aż dojdzie do 100%, czyli około 2 minut.
- Opcje z sekcji „wyłączone” webhook odrzuca komunikatem `must not set the field(s): spec.template.spec.nodeSelector`, dopóki nie włączysz flagi.
- `startupProbe` wymaga podania portu (`readinessProbe` i `livenessProbe` nie). Bez portu webhook **przyjmie** usługę, ale rewizja zawiśnie w `Unknown / Deploying`, bo Kubernetes odrzuci Deployment. Przyczynę widać dopiero w zdarzeniach: `kubectl get events -n demo` → `startupProbe.httpGet.port: Invalid value: 0`.
- `serviceAccountName` musi wskazywać istniejący ServiceAccount (stąd `00-przygotowanie.yaml`).

**`kubectl` czy `kn`?** Każdy plik usługi wdrożysz na dwa sposoby:

```bash
kubectl apply -f $K/01-hello-v1.yaml
kn service apply -n demo -f $K/01-hello-v1.yaml
```

Przy `kn` pamiętaj o dwóch rzeczach:
- **`-n demo` jest obowiązkowe.** `kn` ignoruje `metadata.namespace` z pliku. Bez `-n` usługa wyląduje w namespace bieżącego kontekstu `kubectl` (w próbie: `memeops`, bo tak ustawia go platforma; na czystym klastrze: `default`).
- **`kn` czyta z pliku tylko pierwszy dokument YAML.** Dlatego usługi są w osobnych plikach, a obiekty pomocnicze w `00-przygotowanie.yaml`.

## 1. Pierwsze wdrożenie

```bash
kubectl apply -f $K/01-hello-v1.yaml
kubectl wait ksvc/hello -n demo --for=condition=Ready
kn service list -n demo
kn revision list -n demo
curl $U
```

Oczekiwany wynik: rewizja `hello-v1` ma 100% ruchu, a w odpowiedzi jest `Pozdrowienia z rewizji v1` i na końcu `[v1 · hello-v1 · …]`.

Ostrzeżenie `Kubernetes default value is insecure … securityContext` jest normalne: Knative podpowiada, żeby ustawić `securityContext` (wrócimy do tego w LAB 6). Na wynik nie wpływa.

Zajrzyj, co Knative utworzył z jednego obiektu:

```bash
kubectl get configuration,revision,route,kingress -n demo
kubectl get deploy,pods,svc -n demo
kubectl get pods -n demo -l serving.knative.dev/service=hello \
  -o jsonpath='{.items[0].spec.containers[*].name}'; echo        # user-container queue-proxy
```

## 2. Scale-to-zero i cold start

Nie wysyłaj żądań przez około półtorej minuty i obserwuj pody:

```bash
kubectl get pods -n demo -l serving.knative.dev/service=hello -w     # pod przechodzi w Terminating i znika
```

Potem zmierz pierwsze żądanie (cold) i drugie (warm):

```bash
curl -s -o /dev/null -w 'cold: %{time_total}s\n' $U
curl -s -o /dev/null -w 'warm: %{time_total}s\n' $U
```

Z próby: zero podów po 80 s bez ruchu, **cold start 1,3 s, warm 13 ms**. Różnica to czas, w którym activator trzyma żądanie, a pod startuje. W demie 01 zero przychodzi szybciej (46 s), bo `pierwsza.yaml` ma okno skrócone do 10 s. Tutaj okno jest domyślne (60 s).

## 3. Canary 80/20

```bash
kubectl apply -f $K/02-hello-v2-canary.yaml
kn revision list -n demo
for i in $(seq 20); do curl -s $U | grep '^\['; done | cut -d' ' -f1 | sort | uniq -c
curl -s http://kandydat-hello.demo.127.0.0.1.sslip.io | tail -1
```

Z próby: `hello-v1 80%`, `hello-v2 20% kandydat`. Na 20 żądań wyszło 16 do v1 i 4 do v2. Każde żądanie jest losowane osobno, więc za każdym razem proporcja wyjdzie trochę inna. Adres `kandydat-hello…` zawsze trafia do v2, więc możesz przetestować nową wersję, zanim dostanie więcej ruchu.

Podgląd tego, co dostał Kourier:

```bash
kubectl get kingress hello -n demo \
  -o jsonpath='{range .spec.rules[*]}{.hosts}{" -> "}{range .http.paths[*].splits[*]}{.serviceName}={.percent} {end}{"\n"}{end}'
```

Z próby: hosty `hello.demo…` → `hello-v1=80 hello-v2=20`, hosty `kandydat-hello.demo…` → `hello-v2=100`.

## 4. Pełne przełączenie

```bash
kubectl apply -f $K/03-hello-v2-pelny.yaml
kn revision list -n demo
curl -s $U | tail -1                                               # zawsze v2
curl -s http://poprzednia-hello.demo.127.0.0.1.sslip.io | tail -1   # v1, mimo 0% ruchu
```

Szablon jest taki sam jak w kroku 3, więc **nie powstaje nowa rewizja**. Zmienia się tylko Route. `latestRevision: true` oznacza, że każda kolejna gotowa rewizja od razu dostanie 100% ruchu.

## 5. Rollback

```bash
kn service update hello -n demo --traffic hello-v1=100
curl -s $U | tail -1        # [v1 · hello-v1 · …]
```

Rollback to zmiana ruchu, a nie nowe wdrożenie. Rewizja `hello-v1` cały czas istnieje, więc przełączenie trwa sekundy. Jeśli była przy zerze, dochodzi do tego jeden cold start.

Uwaga: `kn` zmienia obiekt w klastrze, a nie Twoje pliki. Kolejny `kubectl apply -f $K/03-…` przywróci ruch zapisany w pliku. To samo dzieje się w GitOps: źródłem prawdy jest repo.

## 6. Sprzątanie

```bash
kubectl delete ksvc hello -n demo
kubectl delete -f $K/00-przygotowanie.yaml
```

Namespace `demo` zostaje, bo korzystają z niego pozostałe dema. Pełne sprzątanie dem: [`demo/README.md`](../../README.md), sekcja „Sprzątanie”.

## Pułapki, które wyszły w próbie

**Ponowny `apply` tej samej rewizji odrzucony przez webhook.** Pierwsza wersja plików nie miała `name: user-container` ani `successThreshold: 1`. Ponowny `kubectl apply` z tą samą nazwą rewizji kończył się błędem:

```
admission webhook "validation.webhook.serving.knative.dev" denied the request:
Saw the following changes without a name change (-old +new): spec.template.metadata.name
  Containers[0].Name:                      -: "user-container"  +: ""
  Containers[0].ReadinessProbe.SuccessThreshold:  -: "1"  +: "0"
```

Knative uzupełnia te pola wartościami domyślnymi. `apply` ich nie zna, więc je „usuwa”, a dla Knative to zmiana szablonu bez zmiany nazwy rewizji. `--server-side` nie pomaga. Rozwiązanie: wpisać te wartości jawnie (tak jak w plikach tutaj) albo nie nadawać rewizjom własnych nazw (`spec.template.metadata.name`).

**Zmiana szablonu wymaga nowej nazwy rewizji.** Jeśli zmienisz obraz albo env i zostawisz nazwę rewizji, webhook odrzuci zmianę tym samym komunikatem (`Saw the following changes without a name change`), a w różnicy pokaże zmienione pole, np. `Env[0].Value`.

**Nazwa zajęta przez starą rewizję.** Gdy aktualny szablon ma inną nazwę (np. `hello-v1b`), a Ty wgrasz plik z nazwą istniejącej już rewizji (`hello-v2`) i zmienioną treścią, webhook to przepuści. Usługa przejdzie jednak w `Ready=False` z powodem `RevisionNameTaken`: `The revision name "hello-v2" is taken by a conflicting Revision`. Ruch zostaje na starej rewizji. Rozwiązanie: nowa nazwa rewizji.

**Ruch przypięty do nazw rewizji.** Przy `revisionName: hello-v1` w `traffic` każda nowa rewizja dostaje 0% ruchu. To częsty przypadek „wdrożyłem, a nic się nie zmieniło”. Gdy nowa wersja ma dostać ruch od razu, użyj `latestRevision: true`.

## Do samodzielnego sprawdzenia

- Zmień w `02-…` wartość `GREETING` bez zmiany nazwy rewizji i zrób `apply`. Jaki dostaniesz błąd?
- Ustaw `min-scale: "1"` (z nową nazwą rewizji). Czy pod znika po półtorej minuty? Ile teraz trwa pierwsze żądanie?
- Ustaw `target: "1"` i puść równolegle 20 żądań: `seq 20 | xargs -P20 -I{} curl -s -o /dev/null $U`. Ile podów powstało (`kubectl get pods -n demo -l serving.knative.dev/service=hello`)?
