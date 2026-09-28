#!/usr/bin/env bash
# Port-forward every UI and print the logins. Ctrl+C closes them all.
set -uo pipefail

pids=()
trap 'kill "${pids[@]}" 2>/dev/null' EXIT

forward() {   # context namespace service local:remote
  kubectl --context "$1" -n "$2" port-forward "svc/$3" "$4" >/dev/null 2>&1 &
  pids+=($!)
}
secret() {    # namespace secret key
  kubectl --context k3d-cloud -n "$1" get secret "$2" -o "jsonpath={.data.$3}" | base64 -d
}

forward k3d-cloud argocd       argocd-server                  8081:80
forward k3d-cloud monitoring   kube-prometheus-stack-grafana  3000:80
forward k3d-edge  istio-system kiali                          20001:20001
if kubectl argo rollouts version >/dev/null 2>&1; then
  kubectl argo rollouts dashboard --context k3d-edge >/dev/null 2>&1 &
  pids+=($!)
fi

cat <<MSG
ArgoCD          http://localhost:8081         admin / $(secret argocd argocd-initial-admin-secret password)
Grafana         http://localhost:3000/d/shiftnote   admin / $(secret monitoring kube-prometheus-stack-grafana admin-password)
Kiali           http://localhost:20001        (no login)
Argo Rollouts   http://localhost:3100
Ingest API      http://ingest.localhost:9080

Ctrl+C to close.
MSG
wait
