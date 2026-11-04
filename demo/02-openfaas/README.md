# 02 — OpenFaaS CE: instalacja, toolchain i granice

**Cel:** zobaczyć, jak instaluje się OpenFaaS, jak szybko startuje się z gotowymi funkcjami (store, CLI, UI, REST API) i gdzie kończy się wersja Community Edition. To uzasadnia, dlaczego laby robimy na Knative.

`Dzień 1 · blok 1.3`

Dwa terminale: **T1** komendy, **T2** port-forward (zostaje włączony).

## Przygotowanie (raz, przed zajęciami)

`faas-cli` (wersja 0.18.16) do `~/.local/bin` i repozytorium chartów Helm:

```bash
mkdir -p ~/.local/bin
curl -fsSL https://github.com/openfaas/faas-cli/releases/download/0.18.16/faas-cli \
  -o ~/.local/bin/faas-cli          # Linux x86_64; arm64: faas-cli-arm64, Mac M: faas-cli-darwin-arm64
chmod +x ~/.local/bin/faas-cli
helm repo add openfaas https://openfaas.github.io/faas-netes/
```

## Kroki

### 1. Instalacja (ok. 20 s)

```bash
kubectl apply -f https://raw.githubusercontent.com/openfaas/faas-netes/master/namespaces.yml
helm upgrade --install openfaas openfaas/openfaas --version 15.0.13 -n openfaas \
  --set functionNamespace=openfaas-fn --set generateBasicAuth=true --wait
kubectl get pods -n openfaas
```

| Komenda | Co robi |
|---|---|
| `kubectl apply -f namespaces.yml` | tworzy dwa namespace'y: `openfaas` (platforma) i `openfaas-fn` (funkcje) |
| `helm upgrade --install` | instaluje chart (albo aktualizuje, jeśli już jest); `--wait` czeka na gotowe pody |
| `functionNamespace=openfaas-fn` | gdzie będą lądować funkcje |
| `generateBasicAuth=true` | chart losuje hasło admina i zapisuje je w Secrecie `basic-auth` |

👀 Pięć podów: `gateway` (2 kontenery: gateway i faas-netes), `prometheus`, `alertmanager`, `nats`, `queue-worker`.

### 2. Dostęp do gateway i logowanie

```bash
# T2 — zostaw włączone
kubectl -n openfaas port-forward svc/gateway 8080:8080
```

```bash
# T1
export OPENFAAS_URL=http://127.0.0.1:8080
PASSWORD=$(kubectl -n openfaas get secret basic-auth -o jsonpath='{.data.basic-auth-password}' | base64 -d)
echo "$PASSWORD" | faas-cli login -u admin --password-stdin
```

`port-forward` przekierowuje port 8080 z laptopa do Service `gateway` w klastrze. Hasło czytamy z Secretu (base64 → tekst) i podajemy `faas-cli` przez stdin, żeby nie zostało w historii.

### 3. Store

```bash
faas-cli store list | head -20
```

Store to katalog gotowych funkcji (obrazów). Nie ma w nim `cowsay`, jest `cows`.

### 4. Mem v0 z dwóch gotowych funkcji

```bash
faas-cli store deploy figlet
faas-cli store deploy cows
faas-cli list
echo "MemeOps" | faas-cli invoke figlet
curl -s $OPENFAAS_URL/function/cows
```

👀 Napis „MemeOps” w ASCII i krowa. `invoke` i `curl …/function/<nazwa>` to to samo wywołanie przez gateway.

```bash
kubectl get deploy,svc,pods -n openfaas-fn
```

👀 Każda funkcja to zwykły Deployment + Service + pod. Nic więcej.

### 5. UI i REST API

Przeglądarka: http://127.0.0.1:8080/ui/ (login `admin`, hasło: `echo $PASSWORD`) → `figlet` → Invoke.

```bash
curl -s -u admin:$PASSWORD $OPENFAAS_URL/system/functions | python3 -m json.tool | head -20
```

UI i CLI to klienci tego samego REST API, więc da się je wpiąć w dowolny pipeline.

### 6. Szablon Pythona

```bash
faas-cli template store pull python3-http
faas-cli new memeops-hello --lang python3-http --prefix localhost:5001
ls memeops-hello && cat stack.yaml
```

`template store pull` pobiera szablony do katalogu `template/`. `new` tworzy katalog z `handler.py` i dopisuje funkcję do `stack.yaml`. Bez budowania.

Dla bibliotek z kodem C bez gotowych wheeli dla Alpine (musl) jest wariant `python3-http-debian` (Debian, glibc). Pillow akurat ma wheele `musllinux`. Zależności natywne to temat LAB 4.

### 7. Granice CE

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

**Wniosek:** OpenFaaS to najszybszy start i dobry toolchain. Nasz problem to skalowanie od zera do szczytu, a tego w CE nie ma. Zanim wybierzesz framework, przeczytaj tabelę licencji, nie tylko README.

## Sprzątanie

```bash
faas-cli remove figlet          # jedna nazwa na komendę
faas-cli remove cows
rm -rf memeops-hello stack.yaml template
```

Po szkoleniu, całą platformę:

```bash
helm uninstall openfaas -n openfaas
kubectl delete namespace openfaas openfaas-fn
```

## Gdy coś nie działa

| Objaw | Co zrobić |
|---|---|
| `connection refused` na 8080 | port-forward w T2 padł: uruchom go jeszcze raz |
| `faas-cli: command not found` | `export PATH="$HOME/.local/bin:$PATH"` |
| `invalid credentials` w UI | każda instalacja generuje nowe hasło, a przeglądarka pamięta stare: okno incognito, user `admin`, hasło `echo $PASSWORD` |
