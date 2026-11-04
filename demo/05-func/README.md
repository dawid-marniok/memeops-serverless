# 05 — `func` od zera do URL-a

**Cel:** z pustego katalogu do działającej usługi bez Dockerfile'a i bez YAML-a. I czym to się różni od zwykłego kontenera.

`Dzień 1 · blok 1.5` (to samo, co część A w LAB 3)

## Kroki

### 1. Utwórz projekt

```bash
cd ~
func create -l python mem-funkcja
cd mem-funkcja
ls -A
```

`func create -l python` kopiuje szablon funkcji HTTP w Pythonie do nowego katalogu. 👀 Nie ma Dockerfile'a.

### 2. Przeczytaj projekt

```bash
cat func.yaml
cat function/func.py
```

`func.yaml`: nazwa, runtime, rejestr — bez kodu. `func.py`: **handler**, czyli klasa `Function` z metodą `handle`. Serwer HTTP, probe'y (`/health/liveness`, `/health/readiness`) i obraz dostarcza `func`.

### 3. Wdróż

```bash
func deploy --builder=host --registry localhost:5001 --registry-insecure --namespace demo
```

| Flaga | Po co |
|---|---|
| `--builder=host` | buduje obraz na tej maszynie, bez Dockera |
| `--registry localhost:5001` | dokąd wypchnąć obraz |
| `--registry-insecure` | nasz rejestr nie ma TLS |
| `--namespace demo` | gdzie utworzyć Knative Service |

Pierwszy deploy trwa ok. 35 s: build → push → Knative Service.

### 4. Wywołaj i sprawdź obraz

```bash
curl http://mem-funkcja.demo.127.0.0.1.sslip.io/
kubectl get ksvc mem-funkcja -n demo -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

👀 Odpowiedź `OK`. Obraz w usłudze: `localhost:5001/mem-funkcja@sha256:…` — po **digeście**, nie po tagu.

### 5. Zmień odpowiedź funkcji

Otwórz `function/func.py` w edytorze (np. `nano +35 function/func.py`) i w linii `'body': 'OK'.encode(),` zamień `'OK'` na:

```python
'Kiedy func napisal Dockerfile za ciebie\n'
```

### 6. Wdróż drugi raz i porównaj

```bash
func deploy --builder=host --registry localhost:5001 --registry-insecure --namespace demo
curl http://mem-funkcja.demo.127.0.0.1.sslip.io/
kn revision list -n demo -s mem-funkcja
curl -s localhost:5001/v2/mem-funkcja/tags/list; echo
cd ~/memeops
```

👀 Nowa odpowiedź, dwie rewizje (`mem-funkcja-00001`, `-00002`), a w rejestrze tylko jeden tag: `latest`.

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
