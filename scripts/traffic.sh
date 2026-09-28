#!/usr/bin/env bash
# Steady dictation traffic against the edge. Prints status code and serving version,
# so a canary shows up as a mix of versions.
set -uo pipefail
URL=${URL:-http://ingest.localhost:9080/notes}
while true; do
  curl -s -X POST "$URL" -H 'content-type: application/json' \
    -d '{"room":"12","audio_b64":"ZGVtbw=="}' -w ' %{http_code}\n'
  sleep 0.2
done
