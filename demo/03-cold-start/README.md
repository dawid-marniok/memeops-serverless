# 03 — Anatomia cold startu

**Cel:** zobaczyć na żywo dwa obiekty, które decydują o cold starcie: **KPA** mówi, ile podów ma być, a **SKS** mówi, którędy idzie ruch (przez activator czy prosto do poda).

`Dzień 1 · blok 1.4`

Trzy terminale: **T1** i **T2** obserwują, **T3** wykonuje.

## Przygotowanie (ok. 2 min przed demem)

```bash
kubectl apply -f demo/00-namespace.yaml
kubectl apply -f demo/03-cold-start/uslugi.yaml
```

Dwie identyczne usługi `meme-api`. Różnią się jedną adnotacją: `bezposrednio` ma `target-burst-capacity: "0"`. Po ok. minucie bez ruchu obie mają zero podów.

## Kroki

### 1. Obserwuj KPA i SKS

```bash
# T1
kubectl get kpa -n demo -w
```

```bash
# T2
kubectl get sks -n demo -w
```

| Obiekt | Kolumna | Co mówi |
|---|---|---|
| `kpa` (PodAutoscaler) | `DESIREDSCALE` / `ACTUALSCALE` | ile podów chce autoskaler / ile jest |
| `sks` (ServerlessService) | `MODE` | `Proxy` = ruch przez activator, `Serve` = prosto do podów |

Oba obiekty Knative tworzy sam dla każdej rewizji (jeden wiersz = jedna rewizja).

### 2. Sprawdź, że podów nie ma

```bash
# T3
kubectl get pods -n demo
```

👀 Brak podów `przez-activator` i `bezposrednio`. W T2 obie w `Proxy`.

### 3. `przez-activator`: cold, potem warm

```bash
curl -s -o /dev/null -w 'cold: %{time_total} s\n' http://przez-activator.demo.127.0.0.1.sslip.io/
curl -s -o /dev/null -w 'warm: %{time_total} s\n' http://przez-activator.demo.127.0.0.1.sslip.io/
```

👀 cold ok. 1–2 s, warm kilka ms. W T1 `DESIREDSCALE` 0 → 1, zanim `ACTUALSCALE` dojdzie do 1 — ta różnica to cold start. W T2 dalej **`Proxy`**: pod działa, a ruch nadal idzie przez activator.

### 4. `bezposrednio`: cold, potem warm

```bash
curl -s -o /dev/null -w 'cold: %{time_total} s\n' http://bezposrednio.demo.127.0.0.1.sslip.io/
curl -s -o /dev/null -w 'warm: %{time_total} s\n' http://bezposrednio.demo.127.0.0.1.sslip.io/
```

👀 cold tak samo ok. 1–2 s — przy zerze też idzie przez activator. Po starcie poda T2 pokazuje **`Serve`**: Kourier wysyła ruch prosto do poda.

### 5. Nic nie rób i patrz na T1 i T2

👀 `przez-activator` schodzi do 0 ok. 30 s po ostatnim żądaniu. `bezposrednio` najpierw przechodzi z `Serve` na `Proxy`, a pod znika dopiero po ok. 60 s.

## Wynik z próby

| | `przez-activator` | `bezposrednio` |
|---|---|---|
| 0 podów | `Proxy` | `Proxy` |
| cold (obraz w cache) | 1,0–1,9 s | 1,0–1,9 s |
| 1 pod, mały ruch | `Proxy`, warm 6–9 ms | `Serve`, warm 5–14 ms |
| do zera po ostatnim żądaniu | ok. 30 s | ok. 60 s |

## Co tu się stało

- **Przy zerze ktoś musi przytrzymać żądanie.** To robi activator: zgłasza autoskalerowi zapotrzebowanie i czeka na poda. Dlatego cold start jest taki sam w obu usługach.
- **Przy działającym podzie domyślna usługa zostaje w `Proxy`.** Knative trzyma w activatorze zapas na nagły skok ruchu (`target-burst-capacity`, domyślnie 211 żądań). Jeden pod (cel 100) takiego zapasu nie daje. Przy `"0"` zapasu nie ma i ruch idzie prosto do poda.
- **`bezposrednio` wolniej gaśnie.** Przed usunięciem ostatniego poda Knative musi wpiąć activator z powrotem (`Serve` → `Proxy`) i czeka `scale-to-zero-grace-period` (30 s).
- Różnica warm między trybami to ułamek milisekundy. Na latencję działa `min-scale`, nie `target-burst-capacity`.

Okno w `uslugi.yaml` to `30s` (domyślnie 60 s) — tylko po to, żeby gaśnięcie było widać na pokazie. Rób kroki 3 i 4 bez długich przerw, inaczej „warm” wyjdzie znowu cold.

Szczegóły (wzór na tryb SKS, publiczny i prywatny Service, kolumna `ACTIVATORS`, pomiar pod obciążeniem): [`szczegoly.md`](szczegoly.md).

## Sprzątanie

```bash
kubectl delete -f demo/03-cold-start/uslugi.yaml
```
