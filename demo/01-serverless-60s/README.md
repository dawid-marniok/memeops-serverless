# 01 — Serverless w 60 sekund

**Cel:** zobaczyć w jednym przebiegu, co znaczy „serverless na Kubernetesie”: jeden obiekt YAML daje adres HTTP, pod pojawia się na żądanie i znika, gdy nikt nie korzysta.

`Dzień 1 · blok 1.1`

## Kroki

Dwa terminale: w pierwszym obserwujesz pody, w drugim wysyłasz żądania.

```bash
# terminal 1
kubectl get pods -n demo -w
```

```bash
# terminal 2
kubectl apply -f demo/00-namespace.yaml
kubectl apply -f demo/01-serverless-60s/pierwsza.yaml
kubectl wait ksvc/pierwsza -n demo --for=condition=Ready
kubectl get ksvc pierwsza -n demo                 # kolumna URL: adres nadał Knative
curl http://pierwsza.demo.127.0.0.1.sslip.io/
```

Teraz nic nie rób i patrz na terminal 1. Pod przechodzi w `Terminating` i znika. Potem:

```bash
curl -s -o /dev/null -w 'cold: %{time_total} s\n'  http://pierwsza.demo.127.0.0.1.sslip.io/
curl -s -o /dev/null -w 'warm: %{time_total} s\n' http://pierwsza.demo.127.0.0.1.sslip.io/
```

## Wynik z próby

| Co | Wynik |
|---|---|
| od `apply` do pierwszej odpowiedzi | 2,1 s |
| od ostatniego żądania do zera podów | 46 s |
| cold start (pierwsze żądanie przy 0 podów) | 1,42 s |
| warm request | 6 ms |

## Co tu się stało

- Nie było Deploymentu, Service ani Ingressu w YAML-u. Knative utworzył je sam z jednego obiektu `Service` (zobaczysz je w LAB 2).
- Przy zerze podów żądanie odebrał **activator**: przytrzymał je, poprosił o poda i przekazał żądanie, gdy pod był gotowy. Stąd 1,4 s zamiast 6 ms.
- `pierwsza.yaml` ma dwa przyspieszenia tylko na potrzeby pokazu: okno `10s` (domyślnie 60 s) i `timeoutSeconds: 15` (domyślnie 300 s, tyle pod czeka na zakończenie żądań przy wyłączaniu).

**Wniosek:** płacisz za pody tylko wtedy, gdy jest ruch. Ceną jest cold start. Cały pierwszy dzień kręci się wokół tego kompromisu.

## Po demie: krok po kroku i ściąga

W [`krok-po-kroku/`](krok-po-kroku/) jest ta sama usługa rozpisana na pliki YAML: wdrożenie, scale-to-zero, canary 80/20, tagi, rollback (to, co w LAB 2 robisz przez `kn`). Plik [`01-hello-v1.yaml`](krok-po-kroku/01-hello-v1.yaml) jest też **ściągą**: zakomentowane są w nim wszystkie ważniejsze opcje Knative Service z opisem. Do samodzielnej powtórki po LAB 2, około 10 minut.

## Sprzątanie

```bash
kubectl delete ksvc pierwsza -n demo
```
