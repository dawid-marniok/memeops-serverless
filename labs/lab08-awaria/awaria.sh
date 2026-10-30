#!/usr/bin/env bash
# LAB 8: „Piątek 16:55”. Wdraża zgłoszoną przez zespół zmianę, która coś psuje.
# Nie czytaj tego skryptu przed diagnozą — zacznij od objawu (README labu).
# Użycie: labs/lab08-awaria/awaria.sh 1|2|3
set -euo pipefail
N=${1:?podaj numer awarii: 1, 2 albo 3}
IMAGE=localhost:5001/meme-gen:2.2.0; LIMIT=256Mi; SECRET=meme-jwt; VERSION=2.2.1
case $N in
  1) IMAGE=localhost:5001/meme-gen:2.3.0; VERSION=2.3.0 ;;
  2) LIMIT=64Mi; VERSION=2.2.1-oszczednosci ;;
  3) SECRET=meme-jwt-v2; VERSION=2.2.2-rotacja ;;
  *) echo "Nie ma awarii $N" >&2; exit 1 ;;
esac
kubectl apply -f - <<YAML
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: meme-gen
  namespace: memeops
spec:
  template:
    metadata:
      name: meme-gen-zgloszenie-${N}-$(date +%H%M%S)
      annotations:
        autoscaling.knative.dev/target: "5"
        autoscaling.knative.dev/max-scale: "8"
    spec:
      containers:
        - image: ${IMAGE}
          env:
            - {name: APP_VERSION, value: "${VERSION}"}
            - {name: MEME_FORMAT, value: png}
            - name: JWT_SECRET
              valueFrom:
                secretKeyRef: {name: ${SECRET}, key: JWT_SECRET}
          envFrom:
            - configMapRef: {name: meme-config}
          ports:
            - containerPort: 8080
          readinessProbe:
            httpGet: {path: /healthz}
          resources:
            requests: {cpu: 100m, memory: 64Mi}
            limits: {memory: ${LIMIT}}
          securityContext:
            runAsNonRoot: true
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: [ALL]}
            seccompProfile: {type: RuntimeDefault}
  traffic:
    - latestRevision: true
      percent: 100
YAML
echo "Zgłoszenie $N wdrożone. Wróć do README labu i zacznij od objawu."
