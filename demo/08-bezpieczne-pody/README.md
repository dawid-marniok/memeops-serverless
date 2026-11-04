# 08 — Bezpieczne pody i usługi wewnętrzne

**Cel:** dwa ustawienia bezpieczeństwa, które działają bez zmian w kodzie: flaga `secure-pod-defaults` (Knative sam dopisuje `securityContext`) i usługa widoczna tylko wewnątrz klastra.

## Przygotowanie

```bash
kubectl apply -f demo/00-namespace.yaml
kubectl apply -f demo/08-bezpieczne-pody/uslugi.yaml
```

Trzy usługi bez `securityContext`:

| Usługa | Obraz | Po co |
|---|---|---|
| `zwykla` | `meme-api` — w Dockerfile jest `USER 10001` | obraz przygotowany dobrze |
| `jako-root` | `python:3.12-slim` bez `USER` — proces działa jako root | obraz przygotowany źle |
| `wewnetrzna` | `meme-api` z etykietą `cluster-local` | usługa bez adresu publicznego |

## Kroki

### 1. Kto działa jako root?

```bash
curl -s -o /dev/null http://jako-root.demo.127.0.0.1.sslip.io/     # budzi usługę z zera
kubectl exec -n demo deploy/jako-root-00001-deployment -c user-container -- id
```

`kubectl exec … -- id` uruchamia w kontenerze komendę `id`. 👀 `uid=0(root)`.

### 2. Włącz flagę w Knative

```bash
kubectl patch configmap config-features -n knative-serving --type merge \
  -p '{"data":{"secure-pod-defaults":"Enabled"}}'
kubectl get configmap config-features -n knative-serving -o jsonpath='{.data.secure-pod-defaults}'; echo
```

`kubectl patch --type merge` zmienia jedno pole w ConfigMap. Knative czyta je od razu. Flaga dotyczy **całego klastra** i tylko **nowych** rewizji.

### 3. Utwórz nowe rewizje

```bash
kn service update zwykla -n demo --env FLAGA=on
kn service update jako-root -n demo --env FLAGA=on --no-wait
```

Zmienna `FLAGA` nic nie robi — jest tylko po to, żeby powstała nowa rewizja. `--no-wait`: `kn` nie czeka, bo `jako-root` nie wstanie.

### 4. Co dostała każda rewizja

```bash
kubectl get pods -n demo -l serving.knative.dev/revision=zwykla-00002 \
  -o jsonpath='{.items[0].spec.containers[0].securityContext}'; echo
kubectl get pods -n demo -l serving.knative.dev/revision=jako-root-00002
kubectl get ksvc jako-root -n demo
```

👀 `zwykla-00002`: Knative dopisał `runAsNonRoot`, `allowPrivilegeEscalation: false`, `drop: [ALL]`, `seccompProfile`.
👀 `jako-root-00002`: `CreateContainerConfigError`. Usługa: `LATESTREADY jako-root-00001` — ruch został na starej rewizji.

### 5. Usługa tylko wewnątrz klastra

```bash
kubectl get ksvc wewnetrzna -n demo
curl -s -o /dev/null -w '%{http_code}\n' http://wewnetrzna.demo.127.0.0.1.sslip.io/
kubectl run -n demo z-wnetrza --image=curlimages/curl:8.17.0 --rm -i --restart=Never --quiet \
  -- curl -s http://wewnetrzna.demo.svc.cluster.local/
```

`kubectl run … --rm -i` tworzy jednorazowy pod z `curl`, wypisuje wynik i usuwa poda.

👀 URL usługi to `…svc.cluster.local`. Z zewnątrz `404`, z poda w klastrze odpowiedź `[v1 · wewnetrzna-00001 · …]`.

### 6. Wyłącz flagę

```bash
kubectl patch configmap config-features -n knative-serving --type merge \
  -p '{"data":{"secure-pod-defaults":"Disabled"}}'
```

**Zawsze.** Flaga dotyczy całego klastra, a LAB 6 i 7 zakładają stan domyślny.

## Wynik z próby

| Usługa | Bez flagi | Z flagą `Enabled` (nowa rewizja) |
|---|---|---|
| `zwykla` (USER 10001 w obrazie) | `securityContext` pusty | `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault` |
| `jako-root` (obraz bez USER) | działa jako root | `CreateContainerConfigError`: *container has runAsNonRoot and image will run as root*. Ruch zostaje na 00001 |

## Co tu się stało

- `secure-pod-defaults` ma trzy wartości: `Disabled` (domyślnie), `AllowRootBounded` (seccomp i drop capabilities, bez wymuszania non-root) i `Enabled` (dodatkowo `runAsNonRoot: true`).
- Obraz uruchamiany jako root nie wystartuje z `Enabled`. Dowiadujesz się przy wdrożeniu, nie po incydencie. Naprawa jest w obrazie (`USER` w Dockerfile), nie w Knative.
- `cluster-local` to najprostszy sposób na funkcję wewnętrzną (wołaną przez Trigger albo inną usługę).
- W LAB 6 ustawiasz `securityContext` jawnie w manifeście. Flaga to zabezpieczenie dla tych, którzy tego nie zrobią.

## Sprzątanie

```bash
kubectl delete -f demo/08-bezpieczne-pody/uslugi.yaml
```

Flaga musi być `Disabled` (krok 6).
