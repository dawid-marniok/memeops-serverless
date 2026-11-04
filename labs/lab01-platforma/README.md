# lab01 — Platforma pod MemeOps

> **Zgłoszenie od PO:** „Konferencja za dwa dni. Zanim cokolwiek wdrożymy, potrzebujemy platformy, która sama skaluje się od zera do szczytu. Wybraliśmy Knative — postawcie ją.”

**Cel:** sprawdzasz, że klaster z Knative Serving działa, i rozumiesz, z jakich komponentów się składa.

**Zanim zaczniesz:** przeczytaj w [README](../../README.md#praca-na-vm-ce-dadesktop-przeczytaj-przed-lab-1) tabelę „Praca na VM-ce DaDesktop” (kopiowanie komend, Ctrl+C, edytor) i [słowniczek](../../README.md#słowniczek).

**Platforma już stoi.** Twoja VM-ka to klon z gotowym klasterem kind, rejestrem, Knative Serving i Kourierem (postawił je `setup/platform.sh` przed szkoleniem). Nic nie instalujesz, tylko sprawdzasz i czytasz.

## Kroki

| # | Co robisz |
|---|---|
| 1 | Sprawdzenie platformy: `setup/check.sh` |
| 2 | Co postawił `setup/platform.sh` |
| 3 | Komponenty Knative: kto co robi |
| 4 | Usługa `hello` w 30 sekund |

### 1. Sprawdzenie platformy

```bash
cd ~/memeops
export PATH="$HOME/.local/bin:$PATH"
setup/check.sh                 # oczekiwany wynik: SUKCES: 13/13
```

Nie masz 13/13? Uruchom `setup/platform.sh` (skrypt jest idempotentny, można go puścić drugi raz) i napisz na czacie, który punkt `check.sh` nie przeszedł.

### 2. Co postawił `setup/platform.sh`

Otwórz `setup/platform.sh` w edytorze (`pluma setup/platform.sh &` albo `nano setup/platform.sh`, wyjście z nano: **F2**) i przeczytaj, co robi każdy z 6 kroków (rejestr, klaster kind, Knative Serving, Kourier z domeną, obrazy `meme-api`, sprawdzenie). Zwróć uwagę na dwie rzeczy, które nie są oczywiste:
- `config-domain` — skąd wezmą się adresy usług (`*.127.0.0.1.sslip.io`),
- `registries-skipping-tag-resolving` — co Knative normalnie robi z tagiem obrazu (wrócimy do tego w bloku 1.5).

### 3. Komponenty Knative

```bash
kubectl get pods -n knative-serving
kubectl get pods -n kourier-system
kubectl api-resources --api-group=serving.knative.dev
```

Dopasuj komponent do roli (odpowiedzi omawiamy wspólnie):

| Komponent | Rola |
|---|---|
| `controller` | ? |
| `autoscaler` | ? |
| `activator` | ? |
| `webhook` | ? |
| `3scale-kourier-gateway` | ? |

Podpowiedź: jeden z nich „trzyma” żądania, gdy usługa ma zero podów.

### 4. Usługa `hello` w 30 sekund

```bash
kn service create hello -n default --image ghcr.io/knative/helloworld-go:latest --env TARGET=MemeOps
curl http://hello.default.127.0.0.1.sslip.io
kubectl get deploy,pods,svc -n default     # co Knative utworzył za Ciebie?
kn service delete hello -n default
```

## Pytania do zespołu

Zanotuj odpowiedzi — wrócimy do nich na koniec dnia:
1. Ile zasobów zajmuje sama platforma (`kubectl top` nie działa bez metrics-server — użyj `docker stats --no-stream`)?
2. Co by się stało z ruchem, gdyby padł pod `activator`?

## SUKCES

- [ ] `setup/check.sh` → `SUKCES: 13/13`
- [ ] `curl` z kroku 4 (albo przeglądarka na VM) zwrócił `Hello MemeOps!`
- [ ] umiesz powiedzieć, który komponent odpowiada za scale-to-zero, a który za przyjęcie żądania przy zerze podów

## Dla chętnych

- `kubectl get cm -n knative-serving` → przejrzyj `config-autoscaler`: ile trwa stable window i po jakim czasie pod znika?

## Gdy coś nie działa

[`setup/README.md`](../../setup/README.md#gdy-coś-nie-działa)
