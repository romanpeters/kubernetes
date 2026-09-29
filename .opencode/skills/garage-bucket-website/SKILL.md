---
name: garage-bucket-website
description: Expose a static website served from a Garage (S3) bucket at <bucket>.romanpeters.nl, reachable from inside and outside the LAN. Enables the bucket's website access, then creates a Traefik Ingress plus external-dns record mirroring the existing bucket subdomains (cdn, code, based).
metadata:
  audience: homelab maintainers
  workflow: gitops
  opencode/slash: true
---

# Garage Bucket Website

Make a Garage bucket publicly reachable at `<bucket>.romanpeters.nl`, exactly like the existing `cdn.romanpeters.nl`, `code.romanpeters.nl` and `based.romanpeters.nl` bucket sites.

## How it works

- **Garage** (`dxflrs/garage:v2.x`) is S3-compatible object storage in the `infrastructure` namespace. Its `s3_web` `root_domain` is `.romanpeters.nl`, so any bucket is served at `<bucket>.romanpeters.nl` **when a request arrives at the `garage` service `web` port (3902) with that `Host` header** (virtual-host style). No hostname or DNS config is needed in Garage, but the bucket itself must have **website access enabled** (see step 1) — a bucket without it 404s on every path.
- **Traefik** terminates TLS (the `romanpeters-nl-tls` wildcard cert is the default `TLSStore`) and routes by host. Each bucket site needs its own Ingress.
- **Entrypoints**: `websecure-int` = LAN (10.8.x, has the `lan-allow-10-8` middleware); `websecure-pub` = public (exposed). Listing **both** makes the site reachable inside and outside the LAN.
- **DNS**: external-dns creates a **proxied Cloudflare** record (a CNAME to `edge.romanpeters.nl`) for any Ingress carrying the annotation `external-dns: external`. This is what makes it reachable from outside the LAN — but proxied is not the same as public: see the Cloudflare Access check in step 6.
- **Flux** applies `apps/infrastructure` from its explicit `kustomization.yaml` resource list (files are not auto-globbed).

## When to use

Use when a user adds a Garage bucket and wants it reachable at `<bucket>.romanpeters.nl`. Do not use for the S3 API endpoint (that is `s3.romanpeters.nl`) or for the admin UI (`garage.romanpeters.nl`).

## Steps

### 1. Confirm the bucket exists and serves as a website

S3 anonymous access is forbidden, so use the agent credentials from gopass. Print nothing sensitive.

```bash
AKID=$(gopass show garage/agent/access_key_id | tail -1)
SECRET=$(gopass show garage/agent/secret_access_key | tail -1)
kubectl port-forward -n infrastructure svc/garage 13900:3900 13902:3902 &
AWS_ACCESS_KEY_ID="$AKID" AWS_SECRET_ACCESS_KEY="$SECRET" \
  aws s3 ls --endpoint-url http://127.0.0.1:13900 --region garage
```

The bucket must appear in the list. (The Garage admin API on 3903 does not expose a `GET /buckets` list in v2.2.0 — use `aws s3 ls`.)

Then check **website access** for that bucket. The flag is per bucket, not global, and a fresh `garage bucket create` leaves it off, so Garage answers 404 on every path even though the objects are there:

```bash
kubectl exec -n infrastructure deploy/garage -- \
  /garage -c /etc/garage/garage.toml bucket info <bucket>
```

If it reports `Website access: false`, publish the bucket (the index document is the object served for a request ending in `/`):

```bash
kubectl exec -n infrastructure deploy/garage -- \
  /garage -c /etc/garage/garage.toml bucket website --allow --index-document index.html <bucket>
```

Re-run `bucket info` and expect `Website access: true` plus the index document you set. Buckets and this flag live in Garage's own metadata, not in git, so Flux never restores them — re-run these commands after a Garage data restore.

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

Expect the bucket's `index.html`. A 200 here proves Garage resolves the bucket from the host header. A bare 404 (`<h1>404 Not Found</h1>`, not S3's XML `NoSuchKey`) means website access is still off for the bucket — go back to step 1.

### 5. Commit and push

`git add` the new file and `kustomization.yaml`, commit, and push. Pre-commit runs `yamllint`, `yamlfmt`, and the custom `Block public exposure of internal resources` + `Enforce LAN-only protection on websecure-int` hooks — all must pass. If the push is rejected, `git pull --rebase` then push again.

### 6. Verify end-to-end

```bash
sleep 25   # let Flux reconcile
kubectl get ingress -n infrastructure garage-web-<bucket>   # should show the Traefik LB address
curl -sk -o /dev/null -w "%{http_code}\n" https://<bucket>.romanpeters.nl/   # expect 200
```

The public 200 confirms the full path: Cloudflare DNS → Traefik (`websecure-pub`) → Garage `web` port → bucket.

**Then check it from outside the LAN.** A 200 from inside only proves the LAN path. A host covered by a Cloudflare Access application answers `302` to `romanpeters.cloudflareaccess.com` with a `Www-Authenticate: Cloudflare-Access` header for external visitors, while a public host answers straight with the page. Compare against a host that is already public (`based.romanpeters.nl`) using an off-LAN fetcher:

```bash
curl -sk "https://api.hackertarget.com/httpheaders/?q=https://<bucket>.romanpeters.nl/"
```

If it redirects to Cloudflare Access, the host has to be added to the Access bypass/public list next to the other public hosts (`cdn`, `code`, `based`, `tv`, `hello`, `uptime`). That is a Cloudflare dashboard/API change, not a cluster change, and it cannot be done with DNS-scoped API tokens.

## Pitfalls

- **Website access is per bucket, not a global switch.** `garage bucket create` does not enable it; without `garage bucket website --allow` the web port 404s on every path even though `aws s3 ls` lists the objects. This is the usual cause of "the Ingress is up but the site 404s".
- **Proxied is not public.** external-dns makes a proxied Cloudflare record for every annotated Ingress, but Cloudflare Access can still gate the host. Always verify from off-LAN before calling a bucket site public.
- **Secret name is `garage-secrets`** (not `garage`), keys `admin_token` / `metrics_token` / `rpc_secret`.
- **Local Garage ports are plain HTTP.** TLS is at Traefik; `https://127.0.0.1:13902` fails with HTTP 000.
- **Anonymous S3 is blocked.** Always authenticate with the gopass agent keys.
- **The `aws` CLI** (awscli) works against Garage: `--endpoint-url http://...:3900 --region garage`.
- **Forgetting the `kustomization.yaml` entry** is the most common silent failure — the Ingress file exists but is never applied.
- **`external-dns` interval is 1m** with a TXT registry; the Cloudflare record can lag the Ingress by up to a minute.
