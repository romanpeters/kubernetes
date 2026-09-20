---
name: garage-bucket-website
description: Expose a static website served from a Garage (S3) bucket at <bucket>.romanpeters.nl, reachable from inside and outside the LAN. Creates a Traefik Ingress plus external-dns record mirroring the existing bucket subdomains (cdn, code).
metadata:
  audience: homelab maintainers
  workflow: gitops
  opencode/slash: true
---

# Garage Bucket Website

Make a Garage bucket publicly reachable at `<bucket>.romanpeters.nl`, exactly like the existing `cdn.romanpeters.nl` and `code.romanpeters.nl` bucket sites.

## How it works

- **Garage** (`dxflrs/garage:v2.x`) is S3-compatible object storage in the `infrastructure` namespace. Its `s3_web` `root_domain` is `.romanpeters.nl`, so any bucket is served at `<bucket>.romanpeters.nl` **when a request arrives at the `garage` service `web` port (3902) with that `Host` header** (virtual-host style). No per-bucket config in Garage is needed.
- **Traefik** terminates TLS (the `romanpeters-nl-tls` wildcard cert is the default `TLSStore`) and routes by host. Each bucket site needs its own Ingress.
- **Entrypoints**: `websecure-int` = LAN (10.8.x, has the `lan-allow-10-8` middleware); `websecure-pub` = public (exposed). Listing **both** makes the site reachable inside and outside the LAN.
- **DNS**: external-dns creates a **proxied Cloudflare** A record for any Ingress carrying the annotation `external-dns: external`. This is what makes it reachable from outside the LAN.
- **Flux** applies `apps/infrastructure` from its explicit `kustomization.yaml` resource list (files are not auto-globbed).

## When to use

Use when a user adds a Garage bucket and wants it reachable at `<bucket>.romanpeters.nl`. Do not use for the S3 API endpoint (that is `s3.romanpeters.nl`) or for the admin UI (`garage.romanpeters.nl`).

## Steps

### 1. Confirm the bucket exists

S3 anonymous access is forbidden, so use the agent credentials from gopass. Print nothing sensitive.

```bash
AKID=$(gopass show garage/agent/access_key_id | tail -1)
SECRET=$(gopass show garage/agent/secret_access_key | tail -1)
kubectl port-forward -n infrastructure svc/garage 13900:3900 13902:3902 &
AWS_ACCESS_KEY_ID="$AKID" AWS_SECRET_ACCESS_KEY="$SECRET" \
  aws s3 ls --endpoint-url http://127.0.0.1:13900 --region garage
```

The bucket must appear in the list. (The Garage admin API on 3903 does not expose a `GET /buckets` list in v2.2.0 — use `aws s3 ls`.)

### 2. Create the Ingress

Create `apps/infrastructure/garage-web-<bucket>-ingress.yaml` from this template (the plain `cdn` pattern from `garage-web-ingress.yaml`):

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: garage-web-<bucket>
  namespace: infrastructure
  annotations:
    external-dns: external
    traefik.ingress.kubernetes.io/router.entrypoints: websecure-int,websecure-pub
  labels:
    app.kubernetes.io/name: garage-web-<bucket>
    app.kubernetes.io/instance: garage-web-<bucket>-prod
    app.kubernetes.io/part-of: homelab
    app.kubernetes.io/managed-by: flux
    exposure: public
spec:
  ingressClassName: traefik
  rules:
    - host: <bucket>.romanpeters.nl
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: garage
                port:
                  name: web
```

Only add a router middleware (e.g. `code-html-extensionless`, as `code.romanpeters.nl` does) if the site specifically needs it — otherwise keep the plain template.

### 3. Register it

Add `- garage-web-<bucket>-ingress.yaml` to `resources:` in `apps/infrastructure/kustomization.yaml` (the list is explicit; a missing entry means Flux never applies it).

### 4. Sanity-check that Garage serves the bucket

The local port-forward to Garage speaks **plain HTTP** (TLS terminates at Traefik) — use `http://`, not `https://`:

```bash
curl -s -H "Host: <bucket>.romanpeters.nl" http://127.0.0.1:13902/ -w "\nHTTP %{http_code}\n" | head
```

Expect the bucket's `index.html` (or a listing). A 200 here proves Garage resolves the bucket from the host header.

### 5. Commit and push

`git add` the new file and `kustomization.yaml`, commit, and push. Pre-commit runs `yamllint`, `yamlfmt`, and the custom `Block public exposure of internal resources` + `Enforce LAN-only protection on websecure-int` hooks — all must pass. If the push is rejected, `git pull --rebase` then push again.

### 6. Verify end-to-end

```bash
sleep 25   # let Flux reconcile
kubectl get ingress -n infrastructure garage-web-<bucket>   # should show the Traefik LB address
curl -sk -o /dev/null -w "%{http_code}\n" https://<bucket>.romanpeters.nl/   # expect 200
```

The public 200 confirms the full path: Cloudflare DNS → Traefik (`websecure-pub`) → Garage `web` port → bucket.

## Pitfalls

- **Secret name is `garage-secrets`** (not `garage`), keys `admin_token` / `metrics_token` / `rpc_secret`.
- **Local Garage ports are plain HTTP.** TLS is at Traefik; `https://127.0.0.1:13902` fails with HTTP 000.
- **Anonymous S3 is blocked.** Always authenticate with the gopass agent keys.
- **The `aws` CLI** (awscli) works against Garage: `--endpoint-url http://...:3900 --region garage`.
- **Forgetting the `kustomization.yaml` entry** is the most common silent failure — the Ingress file exists but is never applied.
- **`external-dns` interval is 1m** with a TXT registry; the Cloudflare record can lag the Ingress by up to a minute.
