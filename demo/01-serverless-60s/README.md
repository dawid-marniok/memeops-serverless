# 01 — Serverless w 60 sekund

**Cel:** jeden obiekt YAML daje adres HTTP. Pod pojawia się na żądanie i znika, gdy nikt nie korzysta.

Dwa terminale obok siebie: **T1** obserwuje, **T2** wykonuje.

## Kroki

### 1. Obserwuj pody

```bash
# T1
kubectl get pods -n demo -w
```

`-w` (watch) zostawia komendę włączoną i dopisuje każdą zmianę stanu poda.

### 2. Przeczytaj usługę

```bash
# T2
cat demo/01-serverless-60s/pierwsza.yaml
```

Jeden obiekt `Service` z grupy `serving.knative.dev`: obraz i jedna zmienna. Nie ma Deploymentu, Service Kubernetesa ani Ingressu.

### 3. Wdróż

```bash
kubectl apply -f demo/00-namespace.yaml                  # namespace demo (jeśli go nie ma)
kubectl apply -f demo/01-serverless-60s/pierwsza.yaml
kubectl get ksvc pierwsza -n demo
```

Ostrzeżenie `Kubernetes default value is insecure` pomiń — wraca jutro w LAB 6.

👀 Kolumna `URL`: `http://pierwsza.demo.127.0.0.1.sslip.io`. Adres nadał Knative. W T1 pojawia się pod `2/2` — dwa kontenery (Wasz i `queue-proxy`).

### 4. Wywołaj

```bash
curl http://pierwsza.demo.127.0.0.1.sslip.io/
```

### 5. Nic nie rób przez ok. 45 s

👀 W T1 pod przechodzi w `Terminating` i znika. Usługa ma zero podów, a adres dalej działa.

### 6. Zmierz pierwsze i drugie żądanie

```bash
curl -s -o /dev/null -w 'cold: %{time_total} s\n' http://pierwsza.demo.127.0.0.1.sslip.io/
curl -s -o /dev/null -w 'warm: %{time_total} s\n' http://pierwsza.demo.127.0.0.1.sslip.io/
```

`-s` bez paska postępu, `-o /dev/null` bez treści odpowiedzi, `-w` wypisuje tylko czas całego żądania.

👀 cold ok. 1,4 s, warm kilka ms.

## Wynik z próby

| Co | Wynik |
|---|---|
| od `apply` do pierwszej odpowiedzi | 2,1 s |
| od ostatniego żądania do zera podów | 46 s |
| cold start (pierwsze żądanie przy 0 podów) | 1,42 s |
| warm request | 6 ms |

## Co tu się stało

- Knative utworzył Deployment, Service i reguły routingu sam, z jednego obiektu (zobaczysz je w LAB 2).
- Przy zerze podów żądanie odebrał **activator**: przytrzymał je, poprosił o poda i oddał żądanie, gdy pod był gotowy. Stąd 1,4 s zamiast 6 ms.
- `pierwsza.yaml` ma dwa przyspieszenia tylko na pokaz: okno `10s` (domyślnie 60 s) i `timeoutSeconds: 15` (domyślnie 300 s). Domyślnie pod znika po ok. 90 s.

**Wniosek:** płacisz za pody tylko wtedy, gdy jest ruch. Ceną jest cold start.

## Po demie: krok po kroku i ściąga

W [`krok-po-kroku/`](krok-po-kroku/) jest ta sama usługa rozpisana na pliki YAML: wdrożenie, canary 80/20, tagi, rollback (to, co w LAB 2 robisz przez `kn`). [`01-hello-v1.yaml`](krok-po-kroku/01-hello-v1.yaml) to też ściąga z opisem wszystkich ważniejszych opcji Knative Service. Do powtórki po LAB 2.

## Sprzątanie

```bash
kubectl delete ksvc pierwsza -n demo
```
