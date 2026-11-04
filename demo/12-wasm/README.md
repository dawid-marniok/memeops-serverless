# 12 — Wasm: Spin na kind

**Cel:** zobaczyć, że aplikacja WebAssembly działa w Kubernetesie jak zwykły pod (RuntimeClass + shim containerd), i krytycznie ocenić obietnice typu „1000× szybciej”.

`Dzień 2 · blok 2.5`

## Przygotowanie

Demo stawia **osobny klaster** kind `wasm` z obrazem węzła, w którym jest shim Spin. Klaster `memeops` zostaje bez zmian.

```bash
docker pull ghcr.io/spinframework/containerd-shim-spin/kind:v0.26.0     # ok. 400 MB, najlepiej wcześniej
demo/12-wasm/prepare.sh                                                  # ok. 1,5 min
```

## Kroki

### 1. Jak to wpięto w Kubernetes

```bash
head -25 demo/12-wasm/wasm.yaml
kubectl --context kind-wasm get runtimeclass
docker exec wasm-control-plane ls /usr/local/bin | grep shim
```

Kubelet nie wie, że to Wasm. Mówi containerd: uruchom z handlerem `spin`. Shim zamiast `runc` uruchamia moduł w `wasmtime`. Obraz OCI zawiera moduł `.wasm` i `spin.toml` (kilka MB), a nie system plików Linuksa.

### 2. Działa jak zwykły pod

```bash
kubectl --context kind-wasm get pods -o wide
kubectl --context kind-wasm port-forward deploy/wasm-hello 18099:80 &
curl -s localhost:18099/hello; echo; kill %1
```

### 3. Pomiar startu poda

```bash
demo/12-wasm/start.sh wasm-hello
demo/12-wasm/start.sh python-hello
```

## Wynik z próby

| Pod | Od `scale 0 → 1` do Ready |
|---|---|
| `wasm-hello` (Spin, Rust) | 1,0 s |
| `python-hello` (kontener Pythona) | 0,99 s |

Identycznie w próbach 29.10 i 01.11.

## Co tu się stało

- **Brak przewagi w czasie startu poda.** Ten czas to głównie kubelet: sandbox, sieć, probe'y. Sam moduł Wasm wstaje w milisekundach, ale to ginie w kosztach poda.
- Gdzie Wasm naprawdę wygrywa:
  - start **instancji** w milisekundach, gdy runtime już działa: wiele aplikacji w jednym procesie lub podzie (SpinKube, platformy edge),
  - gęstość i izolacja wielu klientów bez osobnego jądra,
  - rozmiar artefaktu (MB zamiast setek MB) i szybka dystrybucja na edge,
  - ten sam moduł na x86 i ARM.
- Ograniczenia: niepełny POSIX (wątki, surowe gniazda; WASI Preview 2 i 3 nadrabia), mało bibliotek z kodem C (Pillow — nie), debugowanie, dojrzałość. SpinKube jest w CNCF Sandbox. Na AKS pule węzłów WASI wycofano 20.07.2025, dziś droga to SpinKube.
- „1000× szybciej” nie ma pierwotnego źródła. Uczciwie: milisekundy zamiast setek milisekund **startu instancji**, dane producentów, niezależne pomiary są mieszane.

**Wniosek:** Wasm to obiecujący kierunek dla gęstości i edge, nie magiczne przyspieszenie poda. Mierz u siebie, na swoim obciążeniu: start instancji i pamięć, nie benchmarki z bloga.

## Sprzątanie

```bash
demo/12-wasm/prepare.sh --delete      # usuwa klaster wasm i wraca do kontekstu kind-memeops
```
