# Dema

Wszystko, co prowadzący pokazuje na ekranie, jest tutaj. Każde demo możesz powtórzyć na swojej VM-ce w trakcie szkolenia albo po nim: README ma cel, kroki, wynik z próby i wniosek.

Wymagają postawionej platformy: `setup/platform.sh` (z `--monitoring` dla dem 06, 07 i 10), a potem `setup/check.sh` → SUKCES 13/13.

| # | Demo | Dzień, blok | Czego dotyczy |
|---|---|---|---|
| 01 | [Serverless w 60 sekund](01-serverless-60s/) | 1 · 1.1 | Jedna usługa Knative: adres, scale-to-zero, cold start. Do powtórki po LAB 2: [`krok-po-kroku/`](01-serverless-60s/krok-po-kroku/) (canary, tagi, rollback w YAML-u + ściąga opcji ksvc) |
| 02 | [OpenFaaS CE: toolchain i granice](02-openfaas/) | 1 · 1.3 | Store, CLI, UI, REST API i to, czego CE nie umie (scale-to-zero, >5 replik) |
| 03 | [Anatomia cold startu](03-cold-start/) | 1 · 1.4 | KPA i SKS na żywo, kiedy activator jest w ścieżce żądania |
| 04 | [Knative Eventing: mem dnia](04-eventing/) | 1 · po LAB 2 | Funkcja wywołana zdarzeniem: PingSource → Broker → Trigger |
| 05 | [`func` od zera do URL-a](05-func/) | 1 · 1.5 | `func create` → handler → `func deploy`, obraz po digeście. Do czytania przed LAB 3: [`handler-vs-kontener.md`](05-func/handler-vs-kontener.md) |
| 06 | [Tryb panic](06-panic/) | 2 · 2.1 | Nagły skok ruchu, okno 6 s vs 60 s, logi autoskalera |
| 07 | [Keynote na domyślnych ustawieniach](07-keynote/) | 2 · LAB 5 | k6 + Grafana: co robi autoskaler, zanim go dostroisz |
| 08 | [Bezpieczne pody i usługi wewnętrzne](08-bezpieczne-pody/) | 2 · 2.2 | `secure-pod-defaults`, obraz jako root, `cluster-local` |
| 09 | [Nieudany rollout](09-nieudany-rollout/) | 2 · 2.4 | `latestCreated` ≠ `latestReady`, stara rewizja dalej działa |
| 10 | [Trace cold startu w Tempo](10-tracing/) | 2 · 2.4 | Knative → OTel Collector → Tempo: gdzie naprawdę idzie czas |
| 11 | [KEDA: skalowanie od kolejki](11-keda/) | 2 · 2.5 | Serverless bez Knative: Deployment 0 → N → 0 według długości kolejki |
| 12 | [Wasm: Spin na kind](12-wasm/) | 2 · 2.5 | WebAssembly jako pod, pomiar startu, krytycznie o „1000× szybciej” |

## Zasady

- Dema mają własną numerację, niezależną od labów: numer dema to kolejność pokazu, a nie numer labu: np. demo 07 (keynote) należy do LAB 5.
- Dema używają namespace'u `demo` ([`00-namespace.yaml`](00-namespace.yaml)), więc nie mieszają się z labami (`memeops`). Wyjątki: demo 07 działa na `meme-gen` z LAB 5 (dashboard Grafany pokazuje namespace `memeops`), demo 02 instaluje OpenFaaS w `openfaas`/`openfaas-fn`, demo 10 dokłada namespace `observability`, a demo 12 stawia osobny klaster kind `wasm`.
- Dema 02, 04, 10, 11 i 12 instalują dodatkowe komponenty skryptem `prepare.sh`. Każdy taki skrypt ma `--delete`, który sprząta po sobie.
- Usługi w demach mają `timeoutSeconds: 15`. Knative ustawia tyle samo czasu na wyłączenie poda, więc pody znikają po kilkunastu sekundach, a nie po 5 minutach (domyślne 300 s).
- Wyniki „z próby” pochodzą z laptopa prowadzącego (kind, 8 CPU) z 01.11.2026. Na VM-ce liczby będą inne, proporcje podobne.

## Sprzątanie

```bash
demo/02-openfaas/prepare.sh --delete
demo/04-eventing/prepare.sh --delete
demo/10-tracing/prepare.sh --delete
demo/11-keda/prepare.sh --delete
demo/12-wasm/prepare.sh --delete
demo/08-bezpieczne-pody/flaga.sh Disabled
kubectl delete ns demo --wait=false
```

Usunięcie namespace'u z podami Knative może trwać kilka minut, dlatego `--wait=false`. Knative ustawia podom `terminationGracePeriodSeconds` równy timeoutowi żądania (domyślnie 300 s), a kontroler namespace'ów sprawdza ponownie dopiero po tym czasie. Większość dem ma `timeoutSeconds: 15`, ale `mem-funkcja` z dema 05 (tworzy ją `func deploy`) ma domyślne 300 s, więc namespace może znikać około 5–7 minut. Jeśli namespace utknie w `Terminating`, nie zdejmuj finalizerów ręcznie: zostaną osierocone obiekty Knative. Poczekaj albo postaw platformę od nowa (`setup/teardown.sh && setup/platform.sh`).
