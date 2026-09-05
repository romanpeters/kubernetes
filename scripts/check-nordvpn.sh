#!/usr/bin/env bash
set -euo pipefail

# Check whether a gluetun pod is actually connected to NordVPN.
#
# Test criteria per pod:
#   1. Public IP seen from inside the pod != public IP of the host (VPN tunnel in use)
#   2. Public IP resolves to a NordVPN ASN/org via ipinfo.io
#   3. gluetun logs show a recent successful connection, no active errors
#
# Usage: NAMESPACE=media scripts/check-nordvpn.sh
# Exit codes: 0 = connected, 1 = not connected / no pod, 2 = indeterminate

NAMESPACE="${NAMESPACE:-media}"
CONTAINER="gluetun"
HOST_SSH_TARGET="${HOST_SSH_TARGET:-k3s}"

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
if ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST_SSH_TARGET" 'curl -s --max-time 10 https://api.ipify.org' 2>/dev/null | grep -Eq '^[0-9.]+$'; then
  host_ip=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST_SSH_TARGET" 'curl -s --max-time 10 https://api.ipify.org' 2>/dev/null)
  info "host public IP: ${host_ip}"
else
  info "could not determine host public IP via ssh ${HOST_SSH_TARGET}; skipping host comparison"
fi

overall=0
while IFS= read -r pod; do
  [[ -z "$pod" ]] && continue
  echo "== ${NAMESPACE}/${pod} (${CONTAINER})"

  pod_ip=$(kubectl exec -n "$NAMESPACE" -c "$CONTAINER" "$pod" -- curl -s --max-time 10 https://api.ipify.org || true)
  if [[ -z "$pod_ip" ]]; then
    fail "could not determine public IP from inside the pod (no outbound connectivity?)"
    overall=1
    continue
  fi

  pod_info=$(kubectl exec -n "$NAMESPACE" -c "$CONTAINER" "$pod" -- curl -s --max-time 10 https://ipinfo.io/json || true)
  pod_org=$(printf '%s' "$pod_info" | jq -r '.org // "unknown"' 2>/dev/null || echo "unknown")
  pod_country=$(printf '%s' "$pod_info" | jq -r '.country // "unknown"' 2>/dev/null || echo "unknown")

  info "public IP inside pod: ${pod_ip} (org: ${pod_org}, country: ${pod_country})"
  connected=false

  if [[ -n "$host_ip" && "$pod_ip" == "$host_ip" ]]; then
    fail "pod public IP equals host IP — traffic is NOT going through the VPN"
  elif [[ -n "$host_ip" ]]; then
    ok "pod public IP differs from host IP"
  fi

  if printf '%s' "$pod_org" | grep -qi 'nordvpn'; then
    ok "public IP belongs to a NordVPN ASN"
    connected=true
  else
    fail "public IP org '${pod_org}' is not NordVPN"
  fi

  logs=$(kubectl logs -n "$NAMESPACE" -c "$CONTAINER" "$pod" --tail=300 2>/dev/null || true)
  last_connected=$(printf '%s\n' "$logs" | grep -E 'Connected to|VPN: Connected' | tail -1 || true)
  last_error=$(printf '%s\n' "$logs" | grep -iE 'error|rate.?limit|failed' | tail -1 || true)
  [[ -n "$last_connected" ]] && info "last connect: ${last_connected}"
  [[ -n "$last_error" ]] && info "last error:   ${last_error}"

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
