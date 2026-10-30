# MemeOps — Serverless na Kubernetes (repo ćwiczeniowe)

Szkolenie NobleProg „Serverless na Kubernetes”, 2 dni. Przez całe szkolenie jesteście zespołem platformowym startupu **MemeOps**: za dwa dni duża konferencja, organizator chce generator memów. Ruch jest nieprzewidywalny — przez większość dnia prawie zero, po keynote kilkaset osób naraz. Klasyczny przypadek dla serverless.

Każdy lab zaczyna się od **zgłoszenia od Product Ownera** i dokłada jeden element do tej samej aplikacji.

## Na start (VM szkoleniowa)

```bash
git clone <adres repo od prowadzącego> memeops && cd memeops
setup/install-tools.sh && export PATH="$HOME/.local/bin:$PATH"
setup/platform.sh          # ok. 5–8 min: klaster kind, rejestr, Knative, obrazy startowe
setup/check.sh             # → SUKCES: 13/13
```

Szczegóły i problemy: [`setup/README.md`](setup/README.md).

## Plan

| Dzień | Lab | Zgłoszenie od PO | Czas |
|---|---|---|---|
| 1 | [lab01 — Platforma](labs/lab01-platforma/) | „Postawcie platformę pod MemeOps” | 30 min |
| 1 | [lab02 — MVP na Knative](labs/lab02-knative-mvp/) | „Wdrażamy MVP, bez przestojów przy zmianach” | 45 min |
| 1 | [lab03 — Funkcja w Pythonie](labs/lab03-funkcja-python/) | „Chcemy własny kod i porządek w wersjach” | 55 min |
| 1 | [lab04 — Zależności natywne](labs/lab04-zaleznosci/) | „Memy ze zdjęciami, nie z tekstu!” | 40 min |
| 2 | [lab05 — Symulacja keynote](labs/lab05-keynote/) | „Po keynote przyjdzie 500 osób naraz. Wytrzymamy?” | 50 min |
| 2 | [lab06 — Sekrety i logowanie](labs/lab06-sekrety/) | „Tylko zalogowani mogą tworzyć memy” | 50 min |
| 2 | [lab07 — CI/CD i canary](labs/lab07-cicd/) | „Nowy szablon dark mode — bezpiecznie” | 45 min |
| 2 | [lab08 — Awaria w piątek 16:55](labs/lab08-awaria/) | „Memy przestały działać!” | 40 min |

## Co jest w repo

| Katalog | Co tam jest |
|---|---|
| [`setup/`](setup/) | instalacja narzędzi i platformy, `check.sh`, przypięte wersje (`versions.env`) |
| [`app/meme-api/`](app/meme-api/) | MVP: mem tekstowy (gotowy obraz `v1`/`v2`) |
| [`app/meme-gen/`](app/meme-gen/) | właściwa funkcja: memy SVG/PNG, galeria, JWT, testy |
| [`templates/python-http/`](templates/python-http/) | „firmowy” szablon funkcji HTTP w Pythonie |
| [`tools/`](tools/) | pomiar cold startu, test obciążenia k6 („keynote”), generator tokenów |
| [`ci/`](ci/) | pipeline lokalny + wzorce GitHub Actions i Azure DevOps |
| [`labs/`](labs/) | laboratoria: zgłoszenie, kroki, warunek SUKCES |

## Zasady

- Kod Pythona jest gotowy. Zmieniasz konfigurację, manifesty i pipeline — w kodzie najwyżej parametry.
- Każdy lab kończy się sekcją **SUKCES**: sprawdzasz ją sam, zanim zgłosisz „gotowe”.
- Utknąłeś? Każdy lab ma sekcję „Dogoń grupę” — jedna komenda doprowadza stan klastra do startu labu.
- Adresy usług: `http://<usługa>.memeops.127.0.0.1.sslip.io` (sslip.io zamienia nazwę na 127.0.0.1, a port 80 VM-ki prowadzi do Kouriera).
