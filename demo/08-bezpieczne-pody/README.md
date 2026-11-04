# 08 — Bezpieczne pody i usługi wewnętrzne

**Cel:** zobaczyć dwa ustawienia bezpieczeństwa, które działają bez zmian w kodzie: flagę `secure-pod-defaults` (Knative sam dopisuje `securityContext`) i usługę widoczną tylko wewnątrz klastra.

`Dzień 2 · blok 2.2`

## Kroki

### 1. Trzy usługi bez `securityContext`

```bash
kubectl apply -f demo/00-namespace.yaml
kubectl apply -f demo/08-bezpieczne-pody/uslugi.yaml
kubectl wait ksvc zwykla jako-root wewnetrzna -n demo --for=condition=Ready
kubectl get ksvc -n demo zwykla jako-root wewnetrzna
kubectl exec -n demo deploy/jako-root-00001-deployment -c user-container -- id
```

Knative ostrzega przy `apply`: `Kubernetes default value is insecure`. Pod `jako-root` działa jako `uid=0(root)`.

### 2. Flaga `secure-pod-defaults`

```bash
demo/08-bezpieczne-pody/flaga.sh Enabled
kn service update zwykla -n demo --env FLAGA=on
kn service update jako-root -n demo --env FLAGA=on --no-wait   # bez --no-wait kn czekałby do 10 min na gotową rewizję
sleep 20
kubectl get pods -n demo -l serving.knative.dev/revision=zwykla-00002 \
  -o jsonpath='{.items[0].spec.containers[0].securityContext}'; echo
kubectl get pods -n demo -l serving.knative.dev/revision=jako-root-00002
kubectl get ksvc jako-root -n demo
```

Flaga działa tylko na **nowe** rewizje, dlatego `kn service update`.

### 3. Usługa tylko wewnątrz klastra

```bash
kubectl get ksvc wewnetrzna -n demo                  # URL: …svc.cluster.local, nie sslip.io
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: wewnetrzna.demo.127.0.0.1.sslip.io' http://127.0.0.1/
kubectl run -n demo z-wnetrza --image=curlimages/curl:8.17.0 --rm -i --restart=Never --quiet \
  --command -- sh -c 'sleep 2; curl -s http://wewnetrzna.demo.svc.cluster.local/ | tail -1'
```

## Wynik z próby

| Usługa | Bez flagi | Z flagą `Enabled` (nowa rewizja) |
|---|---|---|
| `zwykla` (USER 10001 w obrazie) | `securityContext` pusty | `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault` |
| `jako-root` (obraz bez USER) | działa jako root | `CreateContainerConfigError`: *container has runAsNonRoot and image will run as root*. Ruch zostaje na starej rewizji 00001 |

`wewnetrzna`: z zewnątrz Kourier zwraca `404`, nazwa `*.svc.cluster.local` nie rozwiązuje się na VM-ce. Z poda w klastrze odpowiedź `[v1 · wewnetrzna-00001 · …]`.

## Co tu się stało

- `secure-pod-defaults` ma trzy wartości: `Disabled` (domyślnie), `AllowRootBounded` (seccomp i drop capabilities, bez wymuszania non-root) i `Enabled` (dodatkowo `runAsNonRoot: true`, jeśli nie ustawiono inaczej).
- Obraz uruchamiany jako root nie wystartuje z `Enabled`. To dobra wiadomość: dowiadujesz się przy wdrożeniu, nie po incydencie. Naprawa jest w obrazie (`USER` w Dockerfile), nie w Knative.
- `cluster-local` to najprostszy sposób na funkcję wewnętrzną (np. wywoływaną przez Trigger albo inną usługę), której nie wolno wystawić na zewnątrz.
- W LAB 6 ustawiasz `securityContext` jawnie w manifeście. Flaga to zabezpieczenie dla wszystkich, którzy tego nie zrobią.

## Sprzątanie

```bash
demo/08-bezpieczne-pody/flaga.sh Disabled          # flaga dotyczy całego klastra, także labów
kubectl delete -f demo/08-bezpieczne-pody/uslugi.yaml
```
