# media-vpn: NordVPN auth lockout (incident 2026-09-06)

## Symptoms

- `media/media-vpn` pod stuck at 3/4: slskd in CrashLoopBackOff with
  `Failed to resolve address '': Resource temporarily unavailable`
- gluetun logs: `AUTH: Received control message: AUTH_FAILED` repeating every ~10s for hours
- no outbound connectivity from any container in the pod (gluetun kill-switch active)
- pod "worked fine yesterday", then degraded for 1-2 hours before recovering on its own

## Root cause (self-inflicted cascade)

1. gluetun runs a DNS forwarder inside the pod whose upstream default is
   **Cloudflare DoH** (`1.1.1.1`/`1.0.0.1:853`), queried *through the NordVPN tunnel*.
2. DoH connections from the NordVPN egress IP are intermittently RST
   (shared/VPN reputation) — this is **not provider-specific**: switching the
   upstream to Google DoH (`8.8.8.8:853`) produced the same
    `read tcp ...:853: ... connection reset by peer`. Outbound ICMP through
    the tunnel also times out. Plain UDP DNS (port 53) and TLS (443) work fine.
3. gluetun healthchecks depend on that DNS (and on Cloudflare as a target):
   - startup check: resolves `github.com` / `cloudflare.com`
   - full periodic check (every 5 min): dials `cloudflare.com:443` / `github.com:443`
   - small periodic check (every 1 min): ICMP to `1.1.1.1` / `8.8.8.8`
   DoH RSTs make these **fail even though the tunnel itself works**.
4. On healthcheck failure gluetun restarts openvpn (default: restart on failure).
   While DoH keeps RSTing, it restarts every ~10-15s — a restart storm.
5. NordVPN accounts allow **6 concurrent sessions** and every (re)authentication
   registers a new one. The storm fills all 6 slots with ghost sessions of the
   same service credential, so all further auths fail with `AUTH_FAILED`.
6. The lockout is self-sustaining: with the kill-switch on, nothing in the pod
   has internet (slskd crashloops on DNS), and the 10s auth-retry loop keeps the
   slots pinned. It only clears when NordVPN expires the ghost sessions
   (observed: ~1.5h after the storm starts).

The account itself is active and only 2 real clients use it (this pod + one
personal device) — the 6 slots are exhausted by gluetun's own restart churn.

## Prevention (applied 2026-09-07)

Env changes on the gluetun container in `apps/media/media-vpn-deployment.yaml`:

| Env | Value | Why |
|---|---|---|
| `DNS_UPSTREAM_RESOLVERS` | `google` | forwarder upstream instead of the default Cloudflare |
| `DNS_UPSTREAM_RESOLVER_TYPE` | `plain` | DoH (853) is RST from the egress IP regardless of provider; plain UDP 53 works |
| `HEALTH_TARGET_ADDRESSES` | `8.8.8.8:443,9.9.9.9:443` | full check dials raw IPs — no DNS, no Cloudflare |
| `HEALTH_SMALL_CHECK_TYPE` | `dns` | small check (every 1 min) does a plain UDP DNS query instead of ICMP (ICMP egress is blocked) |

All values verified against the running `qmcgaw/gluetun:v3.41.1` binary
(env validation + startup banner) before rollout.

Restart-on-healthcheck-failure stays enabled: it is the right auto-healing for
real tunnel outages, and with every healthcheck path on plain UDP/TLS the
false-positive source is gone.

## Recovery runbook (if it ever recurs)

1. Confirm the lockout: `kubectl -n media get pods` +
   `kubectl -n media logs <media-vpn-pod> -c gluetun | tail -20`
   — continuous `AUTH_FAILED` with no successful connection for >30 min.
   The NordVPN account dashboard shows the 6 active sessions.
2. Stop the churn (frees the sessions): set `replicas: 0` in
   `apps/media/media-vpn-deployment.yaml`, commit + push (Flux scales within
   ~1 min). Emergency alternative: `kubectl -n media scale deploy media-vpn --replicas=0`.
   Media services (slskd/transmission/searxng) lose internet while paused.
3. Wait **>= 60 min** for NordVPN to expire the ghost sessions.
4. Set `replicas: 1` back, commit + push.
5. Verify: `NAMESPACE=media scripts/check-nordvpn.sh` → `PASS`, pod 4/4,
   and no `AUTH_FAILED` in fresh gluetun logs.
