# lab08 — Awaria w piątek 16:55

> **Zgłoszenie od PO:** „Piątek, 16:55. Zespół wypchnął trzy zmiany przed weekendem. Telefony od organizatora się urywają.”

**Cel:** przechodzisz trzy awarie usługi `meme-gen`. W każdej zaczynasz od objawu, dochodzisz do przyczyny i naprawiasz ją jedną zmianą.

**Zasada:** najpierw dowód, potem zmiana. Każdą hipotezę potwierdzasz komendą i wpisujesz do dziennika.

## Jak działa ten lab

Awarii nie musisz psuć sam. Robi to skrypt `awaria.sh`: wdraża „zmianę zespołu”, która coś psuje. Numer w poleceniu wybiera, którą z trzech awarii dostaniesz.

Każda awaria to osobna **runda** i każda wygląda tak samo:

1. `labs/lab08-awaria/awaria.sh <numer>`: skrypt psuje usługę.
2. **Diagnoza:** od objawu dochodzisz do przyczyny i wpisujesz ją do dziennika.
3. **Naprawa:** jedna zmiana w usłudze `meme-gen`.
4. `labs/lab08-awaria/sprawdz.sh`: gdy pokaże `SUKCES: 4/4`, przechodzisz do następnej rundy.

Każda runda zaczyna się od zdrowej usługi i psuje w niej **jedną** rzecz. Awarie się nie sumują: w rundzie 2 nie ma już śladu po rundzie 1.

Nie czytaj `awaria.sh` przed diagnozą. Przyczynę masz znaleźć w klastrze, a nie w skrypcie.

## Kroki

| # | Co robisz |
|---|---|
| 0 | Przygotowanie: zdrowy stan, dziennik, ważna pułapka |
| 1 | Runda 1: „Wdrożyliśmy 2.3.0” |
| 2 | Runda 2: „Obniżyliśmy limity pamięci” |
| 3 | Runda 3: „Zrotowaliśmy klucz JWT” |

### 0. Przygotowanie

```bash
tools/start-lab.sh lab08            # tylko jeśli LAB 7 nie skończony
labs/lab08-awaria/sprawdz.sh        # → SUKCES: 4/4, czyli tak wygląda zdrowa usługa
```

Załóż dziennik `labs/lab08-awaria/dziennik.md` i wklej do niego:

```markdown
| # | Objaw | Hipoteza | Komenda weryfikująca | Wynik | Przyczyna | Poprawka |
|---|---|---|---|---|---|---|
| 1 | | | | | | |
| 2 | | | | | | |
| 3 | | | | | | |
```

**Pułapka (znasz ją z LAB 7):** `awaria.sh` nadaje rewizji własną nazwę (`meme-gen-zgloszenie-N-…`). Poprawka bez **nowej nazwy rewizji** zostanie odrzucona błędem `Saw the following changes without a name change`. Dlatego do każdej naprawy dopisujesz `--revision-name`:

```bash
kn service update meme-gen -n memeops <Twoja poprawka> --revision-name meme-gen-naprawa-1   # w kolejnych rundach: naprawa-2, naprawa-3
```

Wolisz `kubectl edit ksvc meme-gen -n memeops`? Zmień wtedy (albo usuń) pole `spec.template.metadata.name`. Edytor nano zamiast vima: `export KUBE_EDITOR=nano` (zapis **F3** + Enter, wyjście **F2**).

#### Zestaw diagnostyczny

Tych komend używasz w każdej rundzie, najlepiej w tej kolejności:

| Komenda | Co z niej odczytasz |
|---|---|
| `kn service describe meme-gen -n memeops` | która rewizja dostaje ruch i czy usługa jest Ready |
| `kn revision list -n memeops -s meme-gen` | czy najnowsza rewizja jest gotowa (`READY`) i ile ma ruchu (`TRAFFIC`) |
| `kubectl get pods -n memeops -l serving.knative.dev/service=meme-gen` | stan podów (`STATUS`) i liczba restartów (`RESTARTS`) |
| `kubectl describe pod -n memeops <pod>` | sekcje `State` / `Last State` i `Events` na dole: tu zwykle widać przyczynę |
| `kubectl get events -n memeops --sort-by=.lastTimestamp \| tail -20` | ostatnie zdarzenia w namespace |
| `timeout 120 stern -n memeops meme-gen -c user-container` | logi aplikacji ze wszystkich podów na żywo przez 2 minuty |

Jeśli platforma jest zainstalowana z `--monitoring`: Grafana http://localhost:3000 (`admin`/`memeops`) → dashboard **MemeOps — funkcja Knative** (kody odpowiedzi, restarty, OOMKilled).

### 1. Runda 1: „Wdrożyliśmy 2.3.0”

```bash
labs/lab08-awaria/awaria.sh 1
```

- **Zespół mówi:** „Wdrożyliśmy wersję 2.3.0 z nowym szablonem.”
- **Organizator zgłasza:** „Nowego szablonu nie ma. Czy wdrożenie w ogóle poszło?”

Odtwórz objaw: wygeneruj mema na stronie albo sprawdź wersję:

```bash
curl -s http://meme-gen.memeops.127.0.0.1.sslip.io/api/info
```

Pytania naprowadzające: która rewizja faktycznie obsługuje ruch? Czy najnowsza rewizja jest gotowa, a jeśli nie, to co blokuje jej pody?

Napraw, sprawdź (`sprawdz.sh` → 4/4), uzupełnij wiersz 1 dziennika.

### 2. Runda 2: „Obniżyliśmy limity pamięci”

```bash
labs/lab08-awaria/awaria.sh 2
```

- **Zespół mówi:** „Obniżyliśmy limity pamięci, będzie taniej.”
- **Organizator zgłasza:** „Małe memy działają, ale memy HD (`scale` 8) kończą się błędem 502.”

Odtwórz objaw: wyślij mema HD (pierwsza linia pobiera klucz do podpisania tokenu):

```bash
export JWT_SECRET=$(kubectl -n memeops get secret meme-jwt -o jsonpath='{.data.JWT_SECRET}' | base64 -d)
curl -s -XPOST http://meme-gen.memeops.127.0.0.1.sslip.io/api/memes \
  -H "Authorization: Bearer $(tools/token.py test 10)" -d '{"top":"HD","scale":8}' -w ' → %{http_code}\n'
```

Pytania naprowadzające: co się dzieje z podem w chwili wysłania mema HD? Popatrz na `RESTARTS` i na `Last State` w `kubectl describe pod`.

Napraw, sprawdź (`sprawdz.sh` → 4/4), uzupełnij wiersz 2 dziennika.

### 3. Runda 3: „Zrotowaliśmy klucz JWT”

```bash
labs/lab08-awaria/awaria.sh 3
```

- **Zespół mówi:** „Zrotowaliśmy klucz JWT do nowego Secretu.”
- **Organizator zgłasza:** „Po rotacji nowa wersja nie wstaje, a stare tokeny nadal działają. Czy rotacja się udała?”

Pytania naprowadzające: dlaczego nowa rewizja nie startuje? Z której rewizji pochodzą odpowiedzi, skoro stare tokeny działają? Jaki Secret wskazuje nowa rewizja i czy on istnieje?

Masz dwie poprawne drogi naprawy: wycofać zmianę albo dokończyć rotację. Wybierz jedną i zapisz w dzienniku, dlaczego właśnie ją.

Napraw, sprawdź (`sprawdz.sh` → 4/4), uzupełnij wiersz 3 dziennika.

## SUKCES

- [ ] po każdej rundzie `sprawdz.sh` → `SUKCES: 4/4`
- [ ] w dzienniku każda poprawka ma potwierdzoną przyczynę (komenda + wynik)
- [ ] umiesz wyjaśnić, dlaczego w rundach 1 i 3 użytkownicy nadal dostawali memy, a w rundzie 2 już nie

## Dla chętnych

- Zgłoszenie 4 (wymyśl sam): zepsuj coś koledze albo koleżance z grupy jednym poleceniem `kn service update` i podaj im objaw, nie przyczynę.
- Ile trwa, zanim rewizja z rundy 1 dostanie status `False` zamiast `Unknown`? Który parametr o tym decyduje? (`progress-deadline` w `config-deployment`)

## Gdy coś nie działa

| Objaw | Co zrobić |
|---|---|
| `Saw the following changes without a name change` | rewizja potrzebuje nowej nazwy: `kn … --revision-name meme-gen-naprawa-2`, a w YAML-u zmień albo usuń `spec.template.metadata.name` (zobacz krok 0) |
| `sprawdz.sh` czeka długo | pod po OOMKilled się restartuje: poczekaj 20 s i powtórz |
| `sprawdz.sh` przed pierwszą rundą nie daje 4/4 | uruchom `tools/start-lab.sh lab08` |
