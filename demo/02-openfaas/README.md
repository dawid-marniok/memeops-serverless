# 02 — OpenFaaS CE: toolchain i granice

**Cel:** zobaczyć, jak szybko startuje się z OpenFaaS (store, CLI, UI, REST API) i gdzie kończy się wersja Community Edition. To uzasadnia, dlaczego laby robimy na Knative.

`Dzień 1 · blok 1.3`

## Przygotowanie

```bash
demo/02-openfaas/prepare.sh            # OpenFaaS CE (chart 15.0.13) + faas-cli 0.18.16 w ~/.local/bin, ok. 1 min
kubectl -n openfaas port-forward svc/gateway 8080:8080     # w osobnym terminalu, zostaw włączone
```

## Kroki

### 1. Logowanie i store

```bash
export OPENFAAS_URL=http://127.0.0.1:8080
kubectl -n openfaas get secret basic-auth -o jsonpath='{.data.basic-auth-password}' | base64 -d | faas-cli login -u admin --password-stdin
faas-cli store list | head -20
```

Store to katalog gotowych funkcji. Nie ma w nim `cowsay`, jest `cows`.

### 2. Mem v0 z dwóch gotowych funkcji

```bash
faas-cli store deploy figlet && faas-cli store deploy cows
faas-cli list
echo "MemeOps" | faas-cli invoke figlet
curl -s $OPENFAAS_URL/function/cows
```

Wynik: napis „MemeOps” w ASCII i krowa. Od zera do działającej funkcji w trzy minuty.

### 3. UI i REST API

Przeglądarka: http://127.0.0.1:8080/ui/ (login `admin`, hasło z kroku 1) → figlet → Invoke.

```bash
curl -s -u admin:$(kubectl -n openfaas get secret basic-auth -o jsonpath='{.data.basic-auth-password}' | base64 -d) \
  $OPENFAAS_URL/system/functions | python3 -m json.tool | head -20
```

UI i CLI to klienci tego samego REST API, więc da się je wpiąć w dowolny pipeline.

### 4. Szablon Pythona

```bash
faas-cli template store pull python3-http
faas-cli new memeops-hello --lang python3-http --prefix localhost:5001
ls memeops-hello && cat stack.yaml      # faas-cli 0.18 dopisuje funkcję do stack.yaml
```

Dla bibliotek z kodem C bez gotowych wheeli dla Alpine (musl) jest wariant `python3-http-debian` (Debian, glibc). Pillow akurat ma wheele `musllinux`. Zależności natywne to temat LAB 4.

### 5. Granice CE

```bash
kubectl get pods -n openfaas-fn     # po kilku minutach bez ruchu pody nadal 1/1
faas-cli describe figlet
```

| | OpenFaaS CE | OpenFaaS Pro |
|---|---|---|
| scale-to-zero | nie | tak |
| autoskalowanie | tylko RPS, jedna globalna reguła | różne metryki, per funkcja |
| repliki na funkcję | maks. 5 | bez limitu |
| funkcje / namespace'y | 15 / 1 | Standard: 500 / 1, Enterprise: bez limitu namespace'ów |
| użycie komercyjne | 60 dni | licencja |
| sekrety w czasie działania, TLS przez ingress | tak | tak |
| sekrety w czasie budowania | nie | tak |

**Wniosek:** OpenFaaS to najszybszy start i dobry toolchain. Nasz problem to jednak skalowanie od zera do szczytu, a tego w CE nie ma. Zanim wybierzesz framework, przeczytaj tabelę licencji, nie tylko README.

## Sprzątanie

```bash
faas-cli remove figlet cows; rm -rf memeops-hello stack.yaml template
demo/02-openfaas/prepare.sh --delete
```

## Gdy coś nie działa

| Objaw | Co zrobić |
|---|---|
| `connection refused` na 8080 | port-forward padł: uruchom go jeszcze raz |
| `faas-cli: command not found` | `export PATH="$HOME/.local/bin:$PATH"` |
| `invalid credentials` w UI | każda instalacja generuje nowe hasło, a przeglądarka pamięta stare: otwórz UI w oknie incognito, user `admin`, hasło z kroku 1 |
