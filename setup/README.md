# Przygotowanie stanowiska

Pracujesz na swojej VM-ce szkoleniowej (DaDesktop). Wszystko działa lokalnie: klaster **kind** w Dockerze, rejestr obrazów `localhost:5001`, Knative Serving z Kourierem.

## Wymagania

| Co | Minimum | Uwagi |
|---|---|---|
| CPU / RAM | 4 vCPU / 8 GB | z `--monitoring` lepiej 12 GB |
| Docker | działa bez `sudo` | `docker ps` bez błędu |
| Internet | GitHub, Docker Hub, gcr.io, ghcr.io, sslip.io | obrazy Knative i bazowe Pythona |
| Wolny port 80 na 127.0.0.1 | — | inaczej `HTTP_PORT=8080 setup/platform.sh` i dopisuj `:8080` do adresów |

## Kroki

```bash
setup/install-tools.sh                 # kind, kubectl, helm, kn, func, k6, stern → ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"   # dopisz też do ~/.bashrc
setup/platform.sh                      # klaster + Knative + obrazy meme-api
setup/check.sh                         # SUKCES: 13/13
```

Opcje `platform.sh` (można dołożyć później, skrypt jest idempotentny):

| Opcja | Kiedy |
|---|---|
| `--monitoring` | Prometheus + Grafana z dashboardem „MemeOps — funkcja Knative” (LAB 5, LAB 8). Grafana: http://localhost:3000, `admin` / `memeops` |
| `--cert-manager` | HTTPS dla funkcji (LAB 6, dla chętnych) |
| `--bez-obrazow` | ponowne uruchomienie bez budowania `meme-api` |

## Wersje

Wszystkie wersje są przypięte w [`versions.env`](versions.env): Knative 1.23 (wymaga Kubernetesa ≥ 1.34, klaster ma 1.35), k6 2.x, Trivy 0.75.

## Gdy coś nie działa

| Objaw | Co zrobić |
|---|---|
| `permission denied ... docker.sock` | `sudo usermod -aG docker $USER && newgrp docker` |
| `toomanyrequests` przy pobieraniu obrazów | limit Docker Hub — zgłoś prowadzącemu (`docker login`) |
| `address already in use` na porcie 80 | `setup/teardown.sh`, potem `HTTP_PORT=8080 setup/platform.sh` |
| DNS: `*.127.0.0.1.sslip.io` się nie rozwiązuje | sieć blokuje sslip.io: używaj `curl -H "Host: meme-api.memeops.127.0.0.1.sslip.io" http://127.0.0.1/` |
| Knative: pody `Pending` | za mało RAM/CPU: `kubectl describe pod -n knative-serving` → zgłoś prowadzącemu |
| Wszystko się posypało | `setup/teardown.sh && setup/platform.sh` (ok. 6 min) |
