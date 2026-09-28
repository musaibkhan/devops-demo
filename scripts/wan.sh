#!/usr/bin/env bash
# Simulates the care home's WAN link failing: the cloud can no longer reach edge Kafka
# (NodePorts 32100/32101), while nurses keep dictating against the local edge.
#   ./scripts/wan.sh down   -> notes pile up in edge Kafka
#   ./scripts/wan.sh up     -> MirrorMaker2 catches up, the backlog is transcribed
set -euo pipefail
CLI=$(command -v podman || command -v docker)
NODE=k3d-edge-server-0
MATCH=(-p tcp -m multiport --dports 32100,32101 -j DROP)

case "${1:-}" in
  down)
    $CLI exec "$NODE" iptables -t raw -C PREROUTING "${MATCH[@]}" 2>/dev/null \
      || $CLI exec "$NODE" iptables -t raw -I PREROUTING "${MATCH[@]}"
    echo "WAN link DOWN" ;;
  up)
    while $CLI exec "$NODE" iptables -t raw -D PREROUTING "${MATCH[@]}" 2>/dev/null; do :; done
    echo "WAN link UP" ;;
  *)
    echo "usage: $0 down|up" >&2; exit 1 ;;
esac
