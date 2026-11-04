# 03 — Anatomia cold startu

**Cel:** zobaczyć na żywo obiekty, które decydują o cold starcie: KPA (ile podów) i SKS (kto dostaje ruch: activator czy pod), oraz kiedy activator zostaje w ścieżce żądania.

`Dzień 1 · blok 1.4`

## Kroki

```bash
kubectl apply -f demo/00-namespace.yaml
kubectl apply -f demo/03-cold-start/uslugi.yaml
kubectl wait ksvc przez-activator bezposrednio -n demo --for=condition=Ready
```

Dwie identyczne usługi `meme-api`. Różnią się jedną adnotacją: `bezposrednio` ma `target-burst-capacity: "0"`.

### 1. Obserwuj KPA i SKS

```bash
# terminal 1
# -w obserwuje tylko jeden typ zasobu, więc odświeżamy co sekundę
while true; do clear; kubectl get kpa,sks -n demo; sleep 1; done
```

| Obiekt | Co mówi |
|---|---|
| `kpa` (PodAutoscaler) | `DESIREDSCALE` / `ACTUALSCALE`: ile podów chce autoskaler, ile jest |
| `sks` (ServerlessService) | `MODE`: `Proxy` = ruch idzie przez activator, `Serve` = prosto do podów |

**KPA mówi, ile podów ma być, a SKS mówi, którędy idzie ruch.** Oba obiekty Knative tworzy sam dla każdej rewizji. Przy zerze podów SKS jest w `Proxy`, activator przytrzymuje żądanie, a KPA podnosi `DESIREDSCALE` z 0 na 1. Kourier nie bierze w tym udziału: zawsze wysyła ruch do tego samego publicznego Service rewizji.

### 2. Cold start, a zaraz po nim warm requesty

```bash
# terminal 2: poczekaj, aż obie mają 0 podów (ok. 45 s bez ruchu, bezposrednio gaśnie wolniej)
for s in przez-activator bezposrednio; do
  curl -s -o /dev/null -w "$s cold:  %{time_total} s\n" http://$s.demo.127.0.0.1.sslip.io/
  for i in 1 2 3; do
    curl -s -o /dev/null -w "$s warm: %{time_total} s\n" http://$s.demo.127.0.0.1.sslip.io/
  done
done
kubectl get sks -n demo
```

Warm requesty idą od razu po cold w jednej pętli. Usługi mają `window: "10s"`, więc `przez-activator` gaśnie ok. 12 s po ostatnim żądaniu. Z osobną pętlą puszczoną chwilę później kolejne „warm” request byłoby znowu cold startem (~1 s).

Zaraz po cold starcie SKS `bezposrednio` może przez kilka sekund pokazywać `Serve` z `READY Unknown` / `NoHealthyBackends`. To stan przejściowy: tryb już się przełączył, a status gotowości jeszcze nie nadążył. Przy zerze podów `NoHealthyBackends` jest normalne.

Kolumna `ACTIVATORS` mówi, ilu activatorów Knative chce użyć dla rewizji. Liczby z klastra pasują do wzoru `(pody × 100 + TBC) / 100`, zaokrąglonego w górę, minimum 2: dla `przez-activator` 3 przy zerze i 4 przy 1 podzie, dla `bezposrednio` 2. Na kindzie jest jedna replika activatora, więc i tak wszystko idzie przez nią.

### 3. Obserwuj, jak gasną

Zostaw obie usługi bez ruchu i patrz na terminal 1. `przez-activator` schodzi do 0 po ok. 12 s. `bezposrednio` najpierw przechodzi z `Serve` na `Proxy`, a pod znika dopiero po ok. 40 s (patrz punkt 4 w „Co tu się stało”).

Pomiar z tabelą cold/warm (kilka powtórzeń) robi `tools/coldstart.sh przez-activator demo`. Tym samym skryptem zmierzysz cold start sam w LAB 2 (krok 5). Pojedynczy `curl` ma duży rozrzut. Pod obciążeniem (`hey -n 5000 -c 10`, 1 pod) activator dokłada ok. 0,2–0,3 ms na medianie (3,6–3,7 ms vs 3,4 ms).

## Wynik z próby

| Stan | `przez-activator` | `bezposrednio` |
|---|---|---|
| 0 podów | SKS `Proxy` | SKS `Proxy` |
| 1 pod, mały ruch | SKS `Proxy` | SKS `Serve` |
| cold request (pojedynczy `curl`, obraz w cache) | 1,0–1,7 s | 1,0 s |
| warm request | 6–8 ms | 5–7 ms (pojedyncze odchyłki do 15 ms) |
| zejście do 0 po ostatnim żądaniu | ok. 12 s | ok. 42 s |

Cold czasy różnią się między pomiarami o kilkaset ms niezależnie od TBC. Obie usługi startują od zera tak samo, przez activator.

## Co tu się stało

- **Przy zerze podów obie usługi są w trybie `Proxy`.** Ktoś musi przytrzymać żądanie, zanim pod wstanie. To robi activator: zgłasza autoskalerowi zapotrzebowanie (KPA: `DESIREDSCALE 0 → 1`) i czeka na gotowego poda.
- **Przy działających podach domyślna usługa zostaje w `Proxy`.** Knative trzyma w activatorze zapas na nagłe skoki ruchu (`target-burst-capacity`, domyślnie 211 równoczesnych żądań). Dopóki pody nie mają takiego zapasu, ruch idzie przez activator, który buforuje i równo rozkłada żądania.
- `target-burst-capacity: "0"` wyłącza ten zapas: po rozgrzaniu Kourier wysyła ruch prosto do podów (`Serve`). Przy małym ruchu różnica to ułamek milisekundy (pomiar `hey`: ok. 0,3 ms na medianie). Przy nagłym skoku bez activatora żądania trafią do przeciążonych podów.
- **Usługa z `target-burst-capacity: "0"` wolniej schodzi do zera** (ok. 42 s vs 12 s). Zanim Knative usunie ostatniego poda, musi wpiąć activator z powrotem w ścieżkę. Inaczej Kourier wysyłałby ruch do znikającego poda. Przełącza więc SKS z `Serve` na `Proxy` i czeka `scale-to-zero-grace-period` (domyślnie 30 s), aż Envoy na pewno kieruje ruch do activatora. Usługa, która już jest w `Proxy`, tego czekania nie potrzebuje i gaśnie zaraz po oknie (`window: "10s"`). Efekt uboczny: TBC = 0 trzyma pody trochę dłużej, więc rzadziej trafisz na cold start, ale płacisz za ~30 s dodatkowej pracy poda.

**Wniosek:** activator nie jest pojedynczym punktem awarii na stałe w ścieżce. Jest buforem przy zerze i przy skokach ruchu. Jeśli liczy się każda milisekunda (np. near-RT), ustaw `min-scale ≥ 1` i rozważ `target-burst-capacity`, ale świadomie.

## Jak czytać `kubectl get sks`

```
NAME                    MODE    ACTIVATORS   SERVICENAME             PRIVATESERVICENAME              READY     REASON
bezposrednio-00001      Proxy   2            bezposrednio-00001      bezposrednio-00001-private      Unknown   NoHealthyBackends
bezposrednio-00002      Proxy   2            bezposrednio-00002      bezposrednio-00002-private      Unknown   NoHealthyBackends
przez-activator-00001   Proxy   3            przez-activator-00001   przez-activator-00001-private   Unknown   NoHealthyBackends
przez-activator-00002   Proxy   3            przez-activator-00002   przez-activator-00002-private   Unknown   NoHealthyBackends
```

**Jeden wiersz to jedna rewizja, nie usługa.** Po każdej zmianie `spec.template` powstaje nowa rewizja z własnym SKS, a stara zostaje (na zerze podów), żeby dało się do niej wrócić. SKS nie mówi, **która** rewizja dostaje ruch. O tym decyduje Route:

```bash
kubectl get ksvc -n demo
kubectl get ksvc bezposrednio -n demo -o jsonpath='{.status.traffic}'
```

Przy domyślnym `traffic: latestRevision: true` cały ruch idzie do najnowszej rewizji (tu `-00002`). SKS mówi tylko, **jak** ruch dociera do podów danej rewizji.

| Kolumna | Znaczenie |
|---|---|
| `MODE` | `Proxy`: Kourier → activator → pod. `Serve`: Kourier → pod |
| `ACTIVATORS` | ilu activatorów Knative przydziela tej rewizji (wzór niżej) |
| `SERVICENAME` | publiczny Service rewizji: w niego celuje Kourier |
| `PRIVATESERVICENAME` | prywatny Service rewizji: zawsze wskazuje pody |
| `READY` / `REASON` | `Unknown` / `NoHealthyBackends`: za prywatnym Service nie ma gotowego poda. Przy zerze podów to normalny stan spoczynku, nie błąd |

### Publiczny i prywatny Service

Oba to zwykłe obiekty `Service`. Różnią się tym, kto wypełnia ich Endpoints:

| | `bezposrednio-00002-private` | `bezposrednio-00002` |
|---|---|---|
| selector | tak, na pody rewizji | **brak** |
| Endpoints wypełnia | Kubernetes (IP gotowych podów) | Knative (kontroler SKS) |
| w Endpoints | zawsze IP podów | `Proxy`: IP activatorów, `Serve`: IP podów |
| kto używa | activator (gdzie są pody), autoskaler (metryki z queue-proxy) | Kourier |

Przełączenie Proxy ↔ Serve to podmiana listy adresów w publicznym Service. Konfiguracja Kouriera się nie zmienia. Działa to, bo activator i queue-proxy słuchają na tym samym porcie (8012).

```bash
kubectl get svc -n demo -o wide                       # kolumna SELECTOR: tylko -private ma selektor
kubectl get endpointslices -n demo -o wide            # czyje IP są za którym Service
kubectl get pods -n knative-serving -l app=activator -o wide
```

W spoczynku publiczny Service ma IP activatora, a prywatny jest pusty. Po żądaniu prywatny dostaje IP poda. Publiczny w `bezposrednio` też dostaje IP poda (Serve), a w `przez-activator` zostaje przy activatorze.

Szerzej: `docs/01-knative-vs-k8s/index.html`.

## Jak działa `target-burst-capacity`

Gdy pody już działają, Knative wybiera tryb SKS na podstawie **zapasu na nagły skok ruchu** (excess burst capacity):

```
zapas = (gotowe pody × pojemność poda) − bieżące obciążenie − target-burst-capacity
```

- zapas **< 0** → `Proxy`: activator zostaje w ścieżce, żeby zbuforować ewentualny skok
- zapas **≥ 0** → `Serve`: Kourier wysyła ruch prosto do podów

Domyślnie (`config-autoscaler`) pojemność poda to 100 (`container-concurrency-target-default`), a `target-burst-capacity` to 211. Dla 1 poda przy małym ruchu:

| Usługa | Rachunek | Tryb |
|---|---|---|
| `przez-activator` (TBC = 211) | 100 − 0 − 211 = **−111** | `Proxy`. Activator zszedłby ze ścieżki dopiero przy 3 bezczynnych podach (300 ≥ 211) |
| `bezposrednio` (TBC = 0) | przypadek szczególny: zapas = **0** bez liczenia | `Serve` od chwili, gdy pod jest gotowy, niezależnie od obciążenia |

Możliwe wartości adnotacji `autoscaling.knative.dev/target-burst-capacity`:

| Wartość | Zachowanie |
|---|---|
| `"0"` | activator tylko przy zerze podów. Knative ustawia wtedy zapas na sztywno na 0, więc przy działających podach zawsze `Serve` |
| `"211"` (domyślnie) | bufor na ok. 211 dodatkowych równoczesnych żądań |
| `"-1"` | activator **zawsze** w ścieżce, niezależnie od liczby podów |

### Tryb wylicza Knative, TBC to tylko jeden składnik

Trybu SKS nie ustawiasz. Liczy go autoskaler (KPA) przy każdej rekoncyliacji, a ręczną zmianę w SKS nadpisuje. Reguła z kodu (`pkg/reconciler/autoscaling/kpa/kpa.go`):

```
Serve, jeśli autoskaler chce ≥ 1 pod I zapas ≥ 0
w każdym innym przypadku Proxy
```

„Chce ≥ 1 pod” wyjaśnia, dlaczego `bezposrednio` wraca do `Proxy` jeszcze **przed** zniknięciem poda (punkt 3). Na zapas wpływa więcej niż TBC:

| Czynnik | Wpływ | Jak go zmienić |
|---|---|---|
| `target-burst-capacity` | ile zapasu wymagasz | adnotacja w `spec.template` albo `config-autoscaler` |
| liczba gotowych podów | więcej podów = więcej wolnej pojemności | pośrednio: `min-scale`, ruch |
| bieżący ruch | duży ruch zjada zapas, więc wraca `Proxy` | nie zmienisz, zależy od klientów |
| pojemność poda | `containerConcurrency`, adnotacja `target` albo domyślne 100 | w ksvc |

Przykład: domyślne TBC i `min-scale: "3"` dają `Serve` w spoczynku (300 − 0 − 211 ≥ 0). Gdy w toku jest ponad ~89 żądań, rewizja wraca do `Proxy`. Tryb zmienia się razem z ruchem, nie jest stałą cechą usługi.

Wyjątek: przy klasie autoskalera HPA (`autoscaling.knative.dev/class: hpa.autoscaling.knative.dev`) Knative ustawia SKS na stałe w `Serve` i nie bierze TBC pod uwagę (`pkg/reconciler/autoscaling/hpa/hpa.go`). HPA nie skaluje do zera, więc activator nie jest potrzebny.

### Kolumna `ACTIVATORS`

Liczona z bieżącej liczby gotowych podów (`computeNumActivators` w `kpa.go`, `activator-capacity` domyślnie 100):

| TBC | Liczba activatorów |
|---|---|
| `0` | zawsze 2 (minimum) |
| `> 0` | max(2, ⌈(pody × pojemność poda + TBC) / 100⌉) |
| `-1` | max(2, ⌈pody × pojemność poda / 100⌉) |

`przez-activator` (TBC 211): ⌈211 / 100⌉ = **3** przy zerze, ⌈311 / 100⌉ = **4** przy 1 podzie. To liczba żądana. Jeśli w klastrze działa mniej replik activatora, Knative użyje tych, które są.

Kompromis:

- **TBC = 0:** o jeden przeskok mniej, więc mniejsze opóźnienie. Przy nagłym skoku activator **nie wraca** do ścieżki (dopóki jest choć jeden pod). Ruch od razu uderza w istniejące pody i czeka w ich `queue-proxy`, aż autoskaler dołoży nowe. Zejście do zera trwa dłużej o `scale-to-zero-grace-period`.
- **TBC duże albo -1:** każde żądanie ma dodatkowy przeskok. W zamian activator wygładza skoki i równo rozkłada ruch z poszanowaniem `containerConcurrency`.

Czego TBC **nie robi**: nie przyspiesza cold startu. Przy zerze podów każda usługa idzie przez activator, bo tylko on może przytrzymać żądanie. Na cold start pomaga `min-scale ≥ 1`. Szerzej: `docs/05-activator-tbc/index.html`.

## Sprzątanie

```bash
kubectl delete -f demo/03-cold-start/uslugi.yaml
```
