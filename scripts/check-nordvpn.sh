#!/usr/bin/env bash
set -euo pipefail

# Check whether a gluetun pod is actually connected to NordVPN.
#
# Test criteria per pod (the gluetun container only has busybox, so wget is used):
#   1. gluetun logs contain a recent OpenVPN "Peer Connection Initiated" with a *.nordvpn.com server
#   2. Public IP seen from inside the pod != public IP of the host (traffic goes through the tunnel, no leak)
#
# NordVPN servers are not always behind a "NORDVPN" ASN (they run on partner
# infrastructure, e.g. local telecom hosts), so the ipinfo.io org is reported
# for information only and is NOT used as a pass/fail criterion.
#
# Usage: NAMESPACE=media scripts/check-nordvpn.sh
# Exit codes: 0 = connected, 1 = not connected / no pod

NAMESPACE="${NAMESPACE:-media}"
CONTAINER="gluetun"
HOST_SSH_TARGET="${HOST_SSH_TARGET:-k3s}"
MAX_AGE_MIN="${MAX_AGE_MIN:-15}"

info() { printf '  [info] %s\n' "$*"; }
fail() { printf '  [FAIL] %s\n' "$*"; }
ok()   { printf '  [ ok ] %s\n' "$*"; }

PODS=$(
  kubectl get pods -n "$NAMESPACE" -o json | jq -r '
    .items[]
    | select(.status.phase == "Running")
    | select(any(.spec.containers[].name; . == "gluetun"))
    | .metadata.name'
)

if [[ -z "$PODS" ]]; then
  replicas=$(kubectl get deploy -n "$NAMESPACE" -o json | jq -r '[.items[] | select(.metadata.name | test("vpn|slskd|transmission")) | "\(.metadata.name): spec=\(.spec.replicas) ready=\(.status.readyReplicas // 0)"] | join(", ")')
  echo "No running pod with a ${CONTAINER} container in namespace '${NAMESPACE}'."
  [[ -n "$replicas" ]] && info "related deployments: ${replicas}"
  fail "gluetun is NOT connected to NordVPN (no gluetun pod is running)"
  exit 1
fi

host_ip=""
host_ip_raw=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST_SSH_TARGET" 'curl -s --max-time 10 https://api.ipify.org' 2>/dev/null || true)
if printf '%s' "$host_ip_raw" | grep -Eq '^[0-9.]+$'; then
  host_ip="$host_ip_raw"
  info "host public IP: ${host_ip}"
else
  info "could not determine host public IP via ssh ${HOST_SSH_TARGET}; host comparison will be skipped"
fi

overall=0
while IFS= read -r pod; do
  [[ -z "$pod" ]] && continue
  echo "== ${NAMESPACE}/${pod} (${CONTAINER})"

  pod_ip=$(kubectl exec -n "$NAMESPACE" -c "$CONTAINER" "$pod" -- sh -c 'timeout 10 wget -qO- https://api.ipify.org' 2>/dev/null || true)
  if [[ -z "$pod_ip" ]]; then
    fail "no outbound connectivity from inside the pod (kill-switch active / tunnel down)"
    overall=1
    echo
    continue
  fi

  pod_info=$(kubectl exec -n "$NAMESPACE" -c "$CONTAINER" "$pod" -- sh -c 'timeout 10 wget -qO- https://ipinfo.io/json' 2>/dev/null || true)
  pod_org=$(printf '%s' "$pod_info" | jq -r '.org // "unknown"' 2>/dev/null || echo "unknown")
  pod_country=$(printf '%s' "$pod_info" | jq -r '.country // "unknown"' 2>/dev/null || echo "unknown")

  info "public IP inside pod: ${pod_ip} (org: ${pod_org}, country: ${pod_country})"
  connected=true

  if [[ -n "$host_ip" && "$pod_ip" == "$host_ip" ]]; then
    fail "pod public IP equals host IP — traffic is NOT going through the VPN"
    connected=false
  elif [[ -n "$host_ip" ]]; then
    ok "pod public IP differs from host IP"
  else
    info "host public IP unknown; skipping leak check"
  fi

  recent_logs=$(kubectl logs -n "$NAMESPACE" -c "$CONTAINER" "$pod" --since="${MAX_AGE_MIN}m" 2>/dev/null || true)
  connect_line=$(printf '%s\n' "$recent_logs" | grep 'Peer Connection Initiated' | grep 'nordvpn\.com' | tail -1 || true)
  if [[ -n "$connect_line" ]]; then
    ok "connected to NordVPN: ${connect_line}"
  else
    fail "no NordVPN connection in the last ${MAX_AGE_MIN} minutes"
    connected=false
  fi

  last_error=$(printf '%s\n' "$recent_logs" | grep -iE 'rate.?limit|failed to' | tail -1 || true)
  [[ -n "$last_error" ]] && info "recent error: ${last_error}"

  tun=$(kubectl exec -n "$NAMESPACE" -c "$CONTAINER" "$pod" -- sh -c 'awk "/^tun[0-9]+:/{print \$1\" rx=\"\$2\" tx=\"\$17}" /proc/net/dev' 2>/dev/null || true)
  [[ -n "$tun" ]] && info "tun traffic: ${tun}"

  if $connected; then
    ok "${pod} is connected to NordVPN"
  else
    fail "${pod} is NOT connected to NordVPN"
    overall=1
  fi
  echo
done <<< "$PODS"

if [[ $overall -eq 0 ]]; then
  echo "PASS: all gluetun pods are connected to NordVPN"
else
  echo "FAIL: one or more gluetun pods are not connected to NordVPN"
fi
exit "$overall"
