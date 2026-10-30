# lab01 — Platforma pod MemeOps

| Dzień | Czas | Po bloku |
|---|---|---|
| 1 | 30 min | 1.1 Architektura i wybór frameworka |

> **Zgłoszenie od PO:** „Konferencja za dwa dni. Zanim cokolwiek wdrożymy, potrzebujemy platformy, która sama skaluje się od zera do szczytu. Wybraliśmy Knative — postawcie ją.”

**Cel:** masz działający klaster z Knative Serving i rozumiesz, z jakich komponentów się składa.

## Kroki

| # | Co robisz | Czas |
|---|---|---|
| 1 | Narzędzia i platforma | 10 min (skrypt działa sam) |
| 2 | Komponenty Knative | 10 min |
| 3 | Pierwsza usługa w 30 sekund | 5 min |
| 4 | Pytania do zespołu | 5 min |

### 1. Narzędzia i platforma

```bash
setup/install-tools.sh && export PATH="$HOME/.local/bin:$PATH"
setup/platform.sh
setup/check.sh
```

W trakcie przeczytaj `setup/platform.sh`: co robi każdy z 6 kroków? Zwróć uwagę na dwie rzeczy, które nie są oczywiste:
- `config-domain` — skąd wezmą się adresy usług,
- `registries-skipping-tag-resolving` — co Knative normalnie robi z tagiem obrazu.

### 2. Komponenty Knative

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

### 3. Pierwsza usługa w 30 sekund

```bash
kn service create hello -n default --image ghcr.io/knative/helloworld-go:latest --env TARGET=MemeOps
curl http://hello.default.127.0.0.1.sslip.io
kubectl get deploy,pods,svc -n default     # co Knative utworzył za Ciebie?
kn service delete hello -n default
```

### 4. Pytania do zespołu

Zanotuj odpowiedzi — wrócimy do nich na koniec dnia:
1. Ile zasobów zajmuje sama platforma (`kubectl top` nie działa bez metrics-server — użyj `docker stats --no-stream`)?
2. Co by się stało z ruchem, gdyby padł pod `activator`?

## SUKCES

- [ ] `setup/check.sh` → `SUKCES: 13/13`
- [ ] `curl` z kroku 3 zwrócił `Hello MemeOps!`
- [ ] umiesz powiedzieć, który komponent odpowiada za scale-to-zero, a który za przyjęcie żądania przy zerze podów

## Dla chętnych

- `kubectl get cm -n knative-serving` → przejrzyj `config-autoscaler`: ile trwa okno stabilne i po jakim czasie pod znika?

## Gdy coś nie działa

[`setup/README.md`](../../setup/README.md#gdy-coś-nie-działa)
