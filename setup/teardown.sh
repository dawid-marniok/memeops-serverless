#!/usr/bin/env bash
# Usuwa klaster i rejestr MemeOps (np. żeby zacząć LAB 1 od zera).
set -euo pipefail
cd "$(dirname "$0")/.."; source setup/versions.env
kind delete cluster --name "$CLUSTER_NAME"
docker rm -f "$REGISTRY_NAME" 2>/dev/null || true
