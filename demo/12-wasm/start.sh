#!/usr/bin/env bash
# Demo 12: mierzy czas od scale 0→1 do Ready dla Deploymentu (Wasm vs kontener). Użycie: demo/12-wasm/start.sh wasm-hello|python-hello
set -euo pipefail
D=${1:?wasm-hello albo python-hello}; K="kubectl --context kind-wasm"
$K scale deploy/$D --replicas=0 >/dev/null; $K wait pod -l app=$D --for=delete --timeout=60s >/dev/null 2>&1 || true
t0=$(python3 -c 'import time;print(time.time())')
$K scale deploy/$D --replicas=1 >/dev/null
$K wait pod -l app=$D --for=condition=Ready --timeout=60s >/dev/null
python3 -c "import time;print('$D: pod Ready po', round(time.time()-$t0, 2), 's')"
