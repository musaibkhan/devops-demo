#!/usr/bin/env bash
# Shift change: N notes arrive at once. Watch KEDA scale the workers on consumer lag:
#   kubectl --context k3d-cloud -n shiftnote get hpa,pods -w
set -euo pipefail
N=${1:-600}
URL=${URL:-http://ingest.localhost:9080/notes}
echo "Sending $N notes..."
seq "$N" | xargs -P 20 -I{} curl -s -o /dev/null -w '%{http_code}\n' -X POST "$URL" \
  -H 'content-type: application/json' -d '{"room":"{}","audio_b64":"ZGVtbw=="}' | sort | uniq -c
