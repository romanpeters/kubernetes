---
name: garage-bucket-content
description: Update the object content of existing Garage (S3, s3.romanpeters.nl) buckets using awscli with the agent access key. Upload, download, sync, list, and delete objects. Does not create or delete buckets.
metadata:
  audience: homelab maintainers
  workflow: manual
  opencode/slash: true
---

# Garage Bucket Content

Change the *objects* inside an already-existing Garage bucket (upload, download, sync, list, delete) using `awscli` and the **agent** access key.

Out of scope: creating/deleting buckets — the user does that separately. This skill only touches object content.

## How it works

- **Garage** (`dxflrs/garage:v2.x`) is S3-compatible object storage in the `infrastructure` namespace. The S3 API is the `garage` service port `s3` (3900), region `garage`, `root_domain` `.s3.romanpeters.nl`.
- **Endpoints** (pick one):
  - **Local port-forward** (works from anywhere, recommended): `kubectl port-forward` to 3900 → `http://127.0.0.1:13900`. Plain HTTP (TLS terminates at Traefik).
  - **Direct (LAN only)**: `https://s3.romanpeters.nl` — the `garage-s3` Ingress is on the `websecure-int` entrypoint with the `lan-allow-10-8` middleware, so it only resolves from inside the LAN.
- **Credentials**: the **agent** S3 key from gopass (`garage/agent/access_key_id` + `garage/agent/secret_access_key`). Anonymous access is blocked, so always set both.
- **Addressing style = path**: the S3 Ingress only covers the host `s3.romanpeters.nl` (and the local forward is a bare endpoint). awscli defaults to virtual-host style, which would rewrite the URL to `<bucket>.s3.romanpeters.nl` and fail. Force path style so URLs stay `<endpoint>/<bucket>`.

## Setup (run once per shell)

```bash
kubectl port-forward -n infrastructure svc/garage 13900:3900 &
export GARAGE_ENDPOINT=http://127.0.0.1:13900
# On the LAN instead: export GARAGE_ENDPOINT=https://s3.romanpeters.nl

export AWS_ACCESS_KEY_ID="$(gopass show garage/agent/access_key_id | tail -1)"
export AWS_SECRET_ACCESS_KEY="$(gopass show garage/agent/secret_access_key | tail -1)"
export AWS_S3_ADDRESSING_STYLE=path
```

From here on, every `aws` S3 command uses:

```
--endpoint-url "$GARAGE_ENDPOINT" --region garage
```

No secrets are printed — they live only in the env vars above.

## Operations

`B` = bucket name, `P` = object key/path, `DIR` = local directory.

### List

```bash
aws s3 ls --endpoint-url "$GARAGE_ENDPOINT" --region garage                       # all buckets
aws s3 ls "s3://$B/" --endpoint-url "$GARAGE_ENDPOINT" --region garage            # objects in a bucket
aws s3 ls "s3://$B/$P" --endpoint-url "$GARAGE_ENDPOINT" --region garage --recursive
```

### Upload (update content)

```bash
# single file (replaces existing key if present)
aws s3 cp ./local-file "s3://$B/$P" --endpoint-url "$GARAGE_ENDPOINT" --region garage

# whole tree, recursive
aws s3 cp ./DIR/ "s3://$B/" --recursive --endpoint-url "$GARAGE_ENDPOINT" --region garage
```

### Sync (mirror local into the bucket)

```bash
# upload changed/missing objects; leave extra remote objects alone
aws s3 sync ./DIR/ "s3://$B/" --endpoint-url "$GARAGE_ENDPOINT" --region garage

# WARNING: also DELETEs remote objects that are not in ./DIR — only add when you
# truly want the bucket to exactly match the local tree.
aws s3 sync ./DIR/ "s3://$B/" --delete --endpoint-url "$GARAGE_ENDPOINT" --region garage
```

### Download

```bash
aws s3 cp "s3://$B/$P" ./local-file --endpoint-url "$GARAGE_ENDPOINT" --region garage
aws s3 cp "s3://$B/" ./DIR/ --recursive --endpoint-url "$GARAGE_ENDPOINT" --region garage
```

### Delete objects (not the bucket)

```bash
aws s3 rm "s3://$B/$P" --endpoint-url "$GARAGE_ENDPOINT" --region garage           # one key
aws s3 rm "s3://$B/" --recursive --endpoint-url "$GARAGE_ENDPOINT" --region garage # every object
```

Deleting the bucket itself is out of scope for this skill.

## Verify after a change

```bash
aws s3 ls "s3://$B/$P" --endpoint-url "$GARAGE_ENDPOINT" --region garage   # confirm the key is there / gone
aws s3 cp "s3://$B/$P" - --endpoint-url "$GARAGE_ENDPOINT" --region garage | head  # spot-check content
```

## Pitfalls

- **Always set `AWS_S3_ADDRESSING_STYLE=path`.** Without it, awscli builds `<bucket>.s3.romanpeters.nl` (or the bucket into the port-forward host) and the request 404s / can't connect.
- **Anonymous S3 is blocked.** Both agent env vars must be exported, otherwise you get `AccessDenied`/`InvalidAccessKeyId`.
- **`https://s3.romanpeters.nl` is LAN-only.** Off the LAN, use the `http://127.0.0.1:13900` port-forward, not the public host (the Ingress is `websecure-int` + `lan-allow-10-8`).
- **The local forward is plain HTTP** (`http://`), not `https://` — TLS terminates at Traefik, so `https://127.0.0.1:13900` fails with HTTP 000.
- **`--delete` on `aws s3 sync` is destructive** — it removes remote objects missing from the local tree. Confirm scope before running it.
- **The port-forward is a background process.** Kill it when done (`kill %1` / the PID) so it doesn't linger.
