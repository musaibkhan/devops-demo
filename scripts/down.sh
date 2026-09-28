#!/usr/bin/env bash
# Stop the demo.
#   ./scripts/down.sh             stop clusters and the Podman machine; ./scripts/up.sh resumes
#   ./scripts/down.sh --destroy   delete the clusters and all their data
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  "")
    echo "==> Stopping clusters (state is kept)"
    k3d cluster stop cloud edge ;;
  --destroy)
    if command -v podman >/dev/null && [ "$(podman machine inspect --format '{{.State}}')" != "running" ]; then
      podman machine start   # k3d needs the runtime to delete the clusters
    fi
    echo "==> Deleting clusters"
    terraform -chdir=terraform/01-clusters destroy -input=false -auto-approve
    # Everything stage 02 created lived inside the clusters, so its state is now stale.
    rm -f terraform/02-bootstrap/terraform.tfstate terraform/02-bootstrap/terraform.tfstate.backup
    rm -rf terraform/.generated ;;
  *)
    echo "usage: $0 [--destroy]" >&2; exit 1 ;;
esac

if command -v podman >/dev/null; then
  echo "==> Stopping Podman machine (frees its memory)"
  podman machine stop
fi
