# 04 — `func` od zera do URL-a

**Cel:** zobaczyć, co robi Knative Functions: z pustego katalogu do działającej usługi bez Dockerfile'a i bez YAML-a. I czym to się różni od zwykłego kontenera.

`Dzień 1 · blok 1.5` (to samo, co część A w LAB 3)

## Kroki

```bash
REPO=$PWD                              # katalog repo, wracamy tu na końcu
cd ~ && func create -l python mem-funkcja && cd mem-funkcja
ls -A
cat func.yaml
cat function/func.py
```

W katalogu nie ma Dockerfile'a. Jest **handler**: klasa `Function` z metodą `handle`. Serwer HTTP, probe'y (`/health/liveness`, `/health/readiness`) i obraz dostarcza `func`.

```bash
func deploy --builder=host --registry localhost:5001 --registry-insecure --namespace demo
curl http://mem-funkcja.demo.127.0.0.1.sslip.io/
kubectl get ksvc mem-funkcja -n demo -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

`--builder=host` buduje obraz bez Dockera, prosto na Twojej maszynie.

Zmień odpowiedź funkcji i wdróż jeszcze raz:

```bash
perl -pi -e "s/'OK'.encode\(\)/'Kiedy func napisal Dockerfile za ciebie\\\\n'.encode()/" function/func.py
func deploy --builder=host --registry localhost:5001 --registry-insecure --namespace demo
curl http://mem-funkcja.demo.127.0.0.1.sslip.io/
kn revision list -n demo | grep mem-funkcja
curl -s localhost:5001/v2/mem-funkcja/tags/list; echo
cd "$REPO"
```

## Wynik z próby

| Co | Wynik |
|---|---|
| `func create` | poniżej 1 s |
| pierwszy `func deploy` (budowanie + wdrożenie) | 33 s |
| kolejny `func deploy` po zmianie handlera | 15 s |
| rewizje | `mem-funkcja-00001`, `mem-funkcja-00002` |
| obraz w usłudze | `localhost:5001/mem-funkcja@sha256:…` (inny digest dla każdej rewizji) |
| tagi w rejestrze | tylko `latest` |

## Co tu się stało

- **Tag `latest` został nadpisany**, ale każda rewizja wskazuje obraz po **digeście**. Rewizja 00001 nadal uruchamia dokładnie stary kod. W LAB 3 zobaczysz, co się dzieje, gdy wdrażasz po tagu.
- `func` to wygodny start. W LAB 3 dalej pracujemy na firmowym szablonie z Dockerfile'em, bo daje pełną kontrolę nad obrazem (zależności natywne w LAB 4). Porównanie: [`handler-vs-kontener.md`](handler-vs-kontener.md) (wersja graficzna: [`handler-vs-kontener.html`](handler-vs-kontener.html)).

## Sprzątanie

```bash
kn service delete mem-funkcja -n demo
rm -rf ~/mem-funkcja
```
