#!/usr/bin/env bash
# Instaluje narzędzia szkolenia do ~/.local/bin (bez sudo; wyjątki na Linuksie z apt: python3-venv i VS Code, jeśli brakuje). Linux i macOS, amd64 i arm64.
# Docker musi być zainstalowany wcześniej (na VM szkoleniowej jest).
# Użycie: setup/install-tools.sh   potem: export PATH="$HOME/.local/bin:$PATH"
set -euo pipefail
cd "$(dirname "$0")/.."; source setup/versions.env
BIN=${BIN:-$HOME/.local/bin}; mkdir -p "$BIN"
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m); case $ARCH in x86_64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; esac
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
get() { echo "→ $1"; curl -fsSL "$2" -o "$TMP/$1"; }
have() { command -v "$1" >/dev/null && [ -z "${FORCE:-}" ]; }

have kind || { get kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-${OS}-${ARCH}"; install -m 755 "$TMP/kind" "$BIN/kind"; }
have kubectl || { get kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"; install -m 755 "$TMP/kubectl" "$BIN/kubectl"; }
have helm || { get helm.tgz "https://get.helm.sh/helm-${HELM_VERSION}-${OS}-${ARCH}.tar.gz"
  tar -xzf "$TMP/helm.tgz" -C "$TMP"; install -m 755 "$TMP/${OS}-${ARCH}/helm" "$BIN/helm"; }
have kn || { get kn "https://github.com/knative/client/releases/download/${KNATIVE_VERSION}/kn-${OS}-${ARCH}"; install -m 755 "$TMP/kn" "$BIN/kn"; }
have func || { get func "https://github.com/knative/func/releases/download/${KNATIVE_VERSION}/func_${OS}_${ARCH}"; install -m 755 "$TMP/func" "$BIN/func"; }
have stern || { get stern.tgz "https://github.com/stern/stern/releases/download/${STERN_VERSION}/stern_${STERN_VERSION#v}_${OS}_${ARCH}.tar.gz"
  tar -xzf "$TMP/stern.tgz" -C "$TMP"; install -m 755 "$TMP/stern" "$BIN/stern"; }
if ! have k6; then
  if [ "$OS" = darwin ]; then get k6.zip "https://github.com/grafana/k6/releases/download/${K6_VERSION}/k6-${K6_VERSION}-macos-${ARCH}.zip"
    (cd "$TMP" && unzip -q k6.zip); install -m 755 "$TMP/k6-${K6_VERSION}-macos-${ARCH}/k6" "$BIN/k6"
  else get k6.tgz "https://github.com/grafana/k6/releases/download/${K6_VERSION}/k6-${K6_VERSION}-linux-${ARCH}.tar.gz"
    tar -xzf "$TMP/k6.tgz" -C "$TMP"; install -m 755 "$TMP/k6-${K6_VERSION}-linux-${ARCH}/k6" "$BIN/k6"; fi
fi
# LAB 3: `func deploy --builder=host` tworzy virtualenv — na Ubuntu/Debian potrzebny pakiet python3-venv
if [ "$OS" = linux ] && ! python3 -c 'import ensurepip' 2>/dev/null; then
  if command -v apt-get >/dev/null && sudo -n true 2>/dev/null; then echo "→ python3-venv (apt)"; sudo apt-get install -y -qq python3-venv >/dev/null
  else echo "UWAGA: brak python3-venv (LAB 3, func). Zainstaluj: sudo apt install -y python3-venv"; fi
fi
# Edytor dla uczestników na VM: VS Code z oficjalnej paczki .deb (dodaje repo Microsoftu → aktualizacje przez apt)
if [ "$OS" = linux ] && ! command -v code >/dev/null; then
  if command -v apt-get >/dev/null && sudo -n true 2>/dev/null; then
    get code.deb "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-$( [ "$ARCH" = arm64 ] && echo arm64 || echo x64 )"
    echo "code code/add-microsoft-repo boolean true" | sudo debconf-set-selections
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$TMP/code.deb" >/dev/null
  else echo "UWAGA: brak VS Code. Zainstaluj: https://code.visualstudio.com/download"; fi
fi
case $PATH in *"$BIN"*) ;; *) echo; echo "Dodaj do PATH:  export PATH=\"$BIN:\$PATH\"  (najlepiej do ~/.bashrc)";; esac
echo "Gotowe. Dalej: setup/platform.sh"
