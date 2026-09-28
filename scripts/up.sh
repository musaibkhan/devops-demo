#!/usr/bin/env bash
# Start the demo. Resumes stopped clusters (fast, keeps all state), or builds
# everything from scratch with Terraform if the clusters don't exist yet.
set -euo pipefail
cd "$(dirname "$0")/.."

if command -v podman >/dev/null && [ "$(podman machine inspect --format '{{.State}}')" != "running" ]; then
  echo "==> Starting Podman machine"
  podman machine start
fi

if k3d cluster list cloud >/dev/null 2>&1 && k3d cluster list edge >/dev/null 2>&1; then
  echo "==> Resuming clusters"
  k3d cluster start cloud edge
else
  echo "==> Creating clusters and bootstrapping ArgoCD"
  terraform -chdir=terraform/01-clusters init -input=false
  terraform -chdir=terraform/01-clusters apply -input=false -auto-approve
  terraform -chdir=terraform/02-bootstrap init -input=false
  terraform -chdir=terraform/02-bootstrap apply -input=false -auto-approve
fi

echo "==> Waiting for ArgoCD"
kubectl --context k3d-cloud -n argocd rollout status deploy/argocd-server --timeout=5m
kubectl --context k3d-cloud -n argocd rollout status deploy/argocd-repo-server --timeout=5m

cat <<'MSG'

Clusters are up. Pods take a few minutes to settle after a resume. Check with:
  kubectl --context k3d-cloud -n argocd get applications

Open the UIs:  ./scripts/ui.sh
Stop again:    ./scripts/down.sh
MSG
