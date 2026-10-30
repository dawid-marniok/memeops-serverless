# lab07 — CI/CD i canary dla dark mode

| Dzień | Czas | Po bloku |
|---|---|---|
| 2 | 45 min | 2.3 CI/CD i wdrażanie funkcji |

> **Zgłoszenie od PO:** „Mamy szablon dark mode. Chcemy go pokazać 10% uczestników, a jeśli się nie spodoba — wycofać bez dramatu. Do tego ładny adres: `memy.…` zamiast technicznego.”

**Cel:** uruchamiasz pipeline test → build → skan → push → deploy, reagujesz na zatrzymanie przez skaner, wdrażasz canary 10%, promujesz albo wycofujesz i podpinasz własną domenę.

**Zasada:** pipeline, który niczego nie zatrzymuje, niczego nie pilnuje.

## Kroki

| # | Co robisz | Czas |
|---|---|---|
| 1 | Przeczytaj pipeline | 5 min |
| 2 | Pierwsze uruchomienie | 10 min |
| 3 | Naprawa i ponowne uruchomienie | 10 min |
| 4 | Canary: obserwacja, promocja albo wycofanie | 10 min |
| 5 | Własna domena | 5 min |
| 6 | Na prawdziwy CI | 5 min |

### 1. Przeczytaj pipeline

Otwórz `ci/pipeline.sh`. Dla każdego etapu odpowiedz: co go zatrzyma? Porównaj z `ci/github-actions.yml` — czym różni się przypięcie akcji po SHA od tagu `@v0.36.0`?

### 2. Pierwsze uruchomienie

```bash
ci/pipeline.sh 2.2.0 10 dark
```

Pierwsze uruchomienie pobiera bazę Trivy (ok. 1 min). Czy pipeline doszedł do etapu 5? Jeśli nie — który etap go zatrzymał i dlaczego? Przeczytaj tabelę z wynikiem: pakiet, wersja zainstalowana, wersja z poprawką.

### 3. Naprawa i ponowne uruchomienie

Napraw przyczynę **w jednym pliku** (podpowiedź: wróć do tego, co dodałeś w LAB 4), zacommituj i uruchom ponownie:

```bash
git config user.name >/dev/null || git config user.name "Uczestnik MemeOps"
git config user.email >/dev/null || git config user.email "uczestnik@memeops.local"
git add -A && git commit -m "meme-gen: aktualizacja zależności"
ci/pipeline.sh 2.2.0 10 dark
```

✅ Wszystkie 5 etapów zielone, na końcu adres `canary-meme-gen…` i dwie komendy: promocja i wycofanie.

### 4. Canary

```bash
for i in $(seq 1 30); do curl -s http://meme-gen.memeops.127.0.0.1.sslip.io/api/info | grep -o '"theme": "[a-z]*"'; done | sort | uniq -c
curl -s http://canary-meme-gen.memeops.127.0.0.1.sslip.io/api/info
kn revision describe meme-gen-2-2-0 -n memeops | grep -i git-sha
```

Otwórz w przeglądarce adres `canary-…` — tak testerzy widzą dark mode, zanim dostanie go więcej osób. Decyzja PO: promuj na 100% albo wycofaj (komendy wypisał pipeline). Zrób jedno z dwóch i sprawdź `kn revision list -n memeops -s meme-gen`.

### 5. Własna domena

```bash
kubectl apply -f labs/lab07-cicd/domena.yaml
kn domain list -n memeops
curl -s http://memy.127.0.0.1.sslip.io/api/info
```

Przeczytaj komentarz w `domena.yaml`: dlaczego najpierw jest `ClusterDomainClaim`? Co się stanie, gdy drugi zespół spróbuje zmapować tę samą domenę?

### 6. Na prawdziwy CI

Klaster działa na Twojej VM. Runner GitHub Actions w chmurze go nie zobaczy. Wypisz trzy sposoby, żeby etap 5 zadziałał z prawdziwego CI (podpowiedź: komentarze na górze `ci/github-actions.yml` i `ci/azure-pipelines.yml`). Który wybrałbyś u siebie i dlaczego?

## SUKCES

- [ ] masz przebieg pipeline'u zatrzymany przez skaner i przebieg zielony po poprawce
- [ ] rewizja `meme-gen-2-2-0` ma adnotację `memeops/git-sha` z Twoim commitem
- [ ] canary zostało promowane albo wycofane jedną komendą
- [ ] `curl http://memy.127.0.0.1.sslip.io/api/info` odpowiada

## Pułapka, na którą trafisz po tym labie

Pipeline nadaje rewizji nazwę (`--revision-name`). Ta nazwa zostaje w `spec.template.metadata.name`, więc kolejny `kubectl apply` z innym szablonem bez nowej nazwy zostanie odrzucony: `Saw the following changes without a name change`. Rozwiązanie: nowa nazwa albo usunięcie pola `name` z szablonu.

## Dogoń grupę

```bash
tools/dogon.sh lab07
```

**Cliffhanger:** „Piątek, 16:55. Memy przestały się generować…”
