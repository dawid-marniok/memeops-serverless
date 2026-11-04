# MemeOps — Serverless na Kubernetes (repo ćwiczeniowe)

Szkolenie NobleProg „Serverless na Kubernetes”, 2 dni. Przez całe szkolenie jesteście zespołem platformowym startupu **MemeOps**: za dwa dni duża konferencja, organizator chce generator memów. Ruch jest nieprzewidywalny — przez większość dnia prawie zero, po keynote kilkaset osób naraz. Klasyczny przypadek dla serverless.

Każdy lab zaczyna się od **zgłoszenia od Product Ownera** i dokłada jeden element do tej samej aplikacji.

## Na start (VM szkoleniowa)

Na VM-ce DaDesktop wszystko jest już przygotowane: repo leży w `~/memeops`, a platforma działa. Otwórz terminal (prawy przycisk na pulpicie → *Open in Terminal*) i sprawdź:

```bash
cd ~/memeops
setup/check.sh             # → SUKCES: 13/13
```

Stawiasz wszystko od zera (własny komputer, nowa VM)? Wtedy:

```bash
git clone https://github.com/dawid-marniok/memeops-serverless memeops && cd memeops
setup/install-tools.sh && export PATH="$HOME/.local/bin:$PATH"
setup/platform.sh          # klaster kind, rejestr, Knative, obrazy startowe
setup/check.sh             # → SUKCES: 13/13
```

Szczegóły i problemy: [`setup/README.md`](setup/README.md).

## Praca na VM-ce DaDesktop (przeczytaj przed LAB 1)

| Sytuacja | Co robisz |
|---|---|
| Kopiowanie komend z labów | Otwórz to repo w Firefoksie **na VM-ce** (ikona Firefoksa na górnym pasku): https://github.com/dawid-marniok/memeops-serverless. Zaznacz komendę (albo kliknij ikonę kopiowania przy bloku kodu), w terminalu: prawy przycisk → *Paste* |
| Tekst z własnego komputera | DaDesktop sam przenosi schowek Twojego komputera do VM-ki: skopiuj u siebie, w terminalu VM prawy przycisk → *Paste*. Sprawdź przed Enterem, co się wkleiło: w schowku może być coś innego, niż myślisz |
| **Ctrl+C nie przerywa komendy** | W terminalu DaDesktop skróty z Ctrl nie docierają do VM-ki. Komendy, które same się nie kończą, mają w labach `timeout`. Gdy coś utknie: zamknij kartę terminala (×) i otwórz nową (*File → Open Tab*). Nowa karta startuje w tym samym katalogu |
| Drugi terminal | *File → Open Tab* w oknie terminala |
| Edycja plików | Najprościej edytor graficzny: `pluma <plik> &` (zapis: przycisk *Save*). W terminalu: `nano <plik>`, zapis **F3** + Enter, wyjście **F2** (Ctrl+O / Ctrl+X mogą nie działać) |
| `kubectl edit` | Domyślnie otwiera vim. Ustaw nano: `export KUBE_EDITOR=nano` |
| Plik z własnego komputera na VM | Przeciągnij go na pole *Drop file here* na dolnym pasku DaDesktop. Plik pojawi się w `~/uploads-to-dadesktop/` |
| Adres w przeglądarce | Strony usług (np. http://meme-gen.memeops.127.0.0.1.sslip.io) otwierasz w Firefoksie **na VM-ce**, nie na swoim komputerze |

## Słowniczek

| Pojęcie | W jednym zdaniu |
|---|---|
| Knative Service (`ksvc`) | Jeden obiekt, z którego Knative sam tworzy Deployment, Service, adres URL i autoskalowanie |
| Rewizja (revision) | Niezmienna migawka usługi (obraz + konfiguracja); każda zmiana w `spec.template` tworzy nową rewizję |
| Route / traffic split | Reguła, ile procent ruchu trafia do której rewizji (np. 80% v1, 20% v2) |
| Tag rewizji | Osobny adres dla jednej rewizji (np. `kandydat-meme-api…`), bez ruchu produkcyjnego |
| Scale-to-zero | Gdy nie ma ruchu, Knative usuwa wszystkie pody usługi; nic nie kosztuje |
| Cold start | Czas pierwszego żądania, gdy usługa ma zero podów: trzeba uruchomić pod |
| Activator | Komponent Knative, który „trzyma” żądanie, gdy podów jest zero, i budzi usługę |
| Autoscaler / KPA | Komponent, który liczy, ilu podów potrzeba, na podstawie liczby równoczesnych żądań |
| `queue-proxy` | Mały kontener dokładany do każdego poda; mierzy ruch dla autoskalera |
| Kourier | Brama sieciowa (ingress): przyjmuje ruch z portu 80 i kieruje go do usług |
| Digest (`@sha256:…`) | Niezmienny identyfikator obrazu; tag (`:1.0.0`) można nadpisać, digestu nie |
| ConfigMap / Secret | Konfiguracja poza obrazem; Secret na dane wrażliwe (tylko base64, nie szyfrowanie) |
| Canary | Nowa wersja dla małej części ruchu, żeby bezpiecznie sprawdzić ją na produkcji |

## Laby

| Lab | Zgłoszenie od PO |
|---|---|
| [lab01 — Platforma](labs/lab01-platforma/) | „Postawcie platformę pod MemeOps” |
| [lab02 — MVP na Knative](labs/lab02-knative-mvp/) | „Wdrażamy MVP, bez przestojów przy zmianach” |
| [lab03 — Funkcja w Pythonie](labs/lab03-funkcja-python/) | „Chcemy własny kod i porządek w wersjach” |
| [lab04 — Zależności natywne](labs/lab04-zaleznosci/) | „Memy ze zdjęciami, nie z tekstu!” |
| [lab05 — Symulacja keynote](labs/lab05-keynote/) | „Po keynote przyjdzie 500 osób naraz. Wytrzymamy?” |
| [lab06 — Sekrety i logowanie](labs/lab06-sekrety/) | „Tylko zalogowani mogą tworzyć memy” |
| [lab07 — CI/CD i canary](labs/lab07-cicd/) | „Nowy szablon dark mode — bezpiecznie” |
| [lab08 — Awaria w piątek 16:55](labs/lab08-awaria/) | „Memy przestały działać!” |

## Co jest w repo

| Katalog | Co tam jest |
|---|---|
| [`setup/`](setup/) | instalacja narzędzi i platformy, `check.sh`, przypięte wersje (`versions.env`) |
| [`app/meme-api/`](app/meme-api/) | MVP: mem tekstowy (gotowy obraz `v1`/`v2`) |
| [`app/meme-gen/`](app/meme-gen/) | właściwa funkcja: memy SVG/PNG, galeria, JWT, testy |
| [`templates/python-http/`](templates/python-http/) | „firmowy” szablon funkcji HTTP w Pythonie |
| [`demo/`](demo/) | wszystko, co prowadzący pokazuje na ekranie (12 dem): skrypty, YAML, wynik z próby i wniosek — do powtórzenia samemu |
| [`tools/`](tools/) | pomiar cold startu, test obciążenia k6 („keynote”), generator tokenów |
| [`ci/`](ci/) | pipeline lokalny + wzorce GitHub Actions i Azure DevOps |
| [`labs/`](labs/) | laboratoria: zgłoszenie, kroki, warunek SUKCES |
| [`docs/`](docs/) | notatki do nauki: strony HTML z diagramami i pytaniami „Sprawdź się”, ponumerowane w kolejności szkolenia |

## Zasady

- Kod Pythona jest gotowy. Zmieniasz konfigurację, manifesty i pipeline — w kodzie najwyżej parametry.
- Każdy lab kończy się sekcją **SUKCES**: sprawdzasz ją sam, zanim zgłosisz „gotowe”.
- Utknąłeś? Laby od 3 do 7 mają sekcję „Dogoń grupę”, a LAB 8 sekcję „Przed startem”: jedna komenda `tools/start-lab.sh` doprowadza stan klastra do startu labu. Uruchamiaj ją tylko wtedy, gdy nie skończyłeś poprzedniego labu, bo usuwa i tworzy od nowa usługi (tracisz własne rewizje).
- Adresy usług: `http://<usługa>.memeops.127.0.0.1.sslip.io` (sslip.io zamienia nazwę na 127.0.0.1, a port 80 VM-ki prowadzi do Kouriera).
