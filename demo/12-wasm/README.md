# 12 — Wasm: Spin na kind

**Cel:** zobaczyć, że aplikacja WebAssembly działa w Kubernetesie jak zwykły pod (RuntimeClass + shim containerd), i krytycznie ocenić obietnice typu „1000× szybciej”.

`Dzień 2 · blok 2.5`

Dwa terminale: **T1** komendy, **T2** port-forward.

## Przygotowanie (w przerwie, ok. 30 s)

Demo działa na **osobnym klastrze** kind `wasm`, z obrazem węzła, w którym jest shim Spin. Klaster `memeops` zostaje bez zmian.

```bash
docker pull ghcr.io/spinframework/containerd-shim-spin/kind:v0.26.0     # ok. 1 GB — najlepiej dzień wcześniej
kind create cluster --name wasm \
  --image ghcr.io/spinframework/containerd-shim-spin/kind:v0.26.0 \
  --config demo/12-wasm/kind-wasm.yaml
kubectl config use-context kind-memeops                                  # kind przełączył kontekst — wracamy
```

`kind-wasm.yaml` rejestruje w containerd runtime `spin` (binarka shima już jest w obrazie węzła).

## Kroki

### 1. Przełącz się na klaster `wasm`

```bash
kubectl config use-context kind-wasm
```

Od teraz każde `kubectl` trafia do klastra `wasm`. Na końcu wracamy (krok 6).

### 2. RuntimeClass i shim

```bash
cat demo/12-wasm/1-runtimeclass.yaml
kubectl apply -f demo/12-wasm/1-runtimeclass.yaml
kubectl get runtimeclass
docker exec wasm-control-plane ls /usr/local/bin | grep shim
```

RuntimeClass `wasmtime-spin-v2` wskazuje handler `spin` w containerd. `docker exec` zagląda do węzła kind (to kontener Dockera). 👀 Obok zwykłego `containerd-shim-runc-v2` jest `containerd-shim-spin-v2`.

Kubelet nie wie, że to Wasm. Mówi containerd: uruchom z handlerem `spin`. Shim zamiast `runc` uruchamia moduł w `wasmtime`.

### 3. Dwie aplikacje: Wasm i Python

```bash
cat demo/12-wasm/2-aplikacje.yaml
kubectl apply -f demo/12-wasm/2-aplikacje.yaml
kubectl rollout status deploy/wasm-hello deploy/python-hello
kubectl get pods -o wide
```

`wasm-hello` ma `runtimeClassName: wasmtime-spin-v2`, a jego obraz OCI zawiera moduł `.wasm` i `spin.toml` (kilka MB). `python-hello` to zwykły kontener. 👀 Dla Kubernetesa oba to zwykłe pody.

### 4. Działa jak zwykły pod

```bash
# T2 — zostaw włączone
kubectl port-forward deploy/wasm-hello 18099:80
```

```bash
# T1
curl -s localhost:18099/hello; echo
```

👀 `Hello world from Spin!`

### 5. Pomiar startu poda

Najpierw zero replik, potem czas od `scale 1` do gotowego poda:

```bash
kubectl scale deploy/wasm-hello --replicas=0
time (kubectl scale deploy/wasm-hello --replicas=1 && kubectl rollout status deploy/wasm-hello)
```

```bash
kubectl scale deploy/python-hello --replicas=0
time (kubectl scale deploy/python-hello --replicas=1 && kubectl rollout status deploy/python-hello)
```

`time ( … )` mierzy obie komendy razem. `rollout status` kończy się, gdy pod jest gotowy. Przed drugą komendą odczekaj, aż stary pod zniknie (`kubectl get pods`). 👀 Ostatnia linia `time`, wartość `total`.

### 6. Wróć na klaster szkolenia

```bash
kubectl config use-context kind-memeops
```

## Wynik z próby

| Pod | Od `scale 0 → 1` do Ready |
|---|---|
| `wasm-hello` (Spin, Rust) | 1,0 s |
| `python-hello` (kontener Pythona) | 0,99–1,0 s |

Identycznie w próbach 29.10, 01.11 i 04.11.

## Co tu się stało

- **Brak przewagi w czasie startu poda.** Ten czas to głównie kubelet: sandbox, sieć, probe'y. Sam moduł Wasm wstaje w milisekundach, ale to ginie w kosztach poda.
- Gdzie Wasm naprawdę wygrywa:
  - start **instancji** w milisekundach, gdy runtime już działa: wiele aplikacji w jednym procesie lub podzie (SpinKube, platformy edge),
  - gęstość i izolacja wielu klientów bez osobnego jądra,
  - rozmiar artefaktu (MB zamiast setek MB) i szybka dystrybucja na edge,
  - ten sam moduł na x86 i ARM.
- Ograniczenia: niepełny POSIX (wątki, surowe gniazda; WASI Preview 2 i 3 nadrabia), mało bibliotek z kodem C (Pillow — nie), debugowanie, dojrzałość. SpinKube jest w CNCF Sandbox. Na AKS pule węzłów WASI wycofano 20.07.2025, dziś droga to SpinKube.
- „1000× szybciej” nie ma pierwotnego źródła. Uczciwie: milisekundy zamiast setek milisekund **startu instancji**, dane producentów, niezależne pomiary są mieszane.

**Wniosek:** Wasm to obiecujący kierunek dla gęstości i edge, nie magiczne przyspieszenie poda. Mierz u siebie, na swoim obciążeniu.

## Sprzątanie

```bash
kind delete cluster --name wasm
kubectl config use-context kind-memeops
```
