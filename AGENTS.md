# Kubernetes Homelab Project

This project manages a homelab infrastructure using Kubernetes (K3s), FluxCD, and GitOps practices.

## Project Overview

This repository implements a single-node K3s cluster running on Kairos OS within Proxmox, managed through FluxCD for GitOps deployment. The cluster hosts various applications and services including media servers, monitoring tools, development environments, and infrastructure components.

## Architecture

### Cluster Components
- **K3s Cluster**: Single-node Kubernetes cluster running on Kairos OS
- **Networking**: Traefik as ingress controller with websecure-int and websecure-pub routes
- **CNI**: Cilium for networking
- **Certificate Management**: cert-manager for TLS certificates
- **DNS**: ExternalDNS for external domain management

### Application Overview

The cluster hosts applications organized into namespaces:
- **System Namespace**: Core infrastructure components (Traefik, Cilium, cert-manager, ExternalDNS)
- **General Namespace**: User-facing applications (Heimdall, Gitea, Homebox, n8n)
- **Automation Namespace**: Automation tools (AWX + Operator)
- **Media Namespace**: Media server applications (Jellyfin, Overseerr, Immich, etc.)
- **Monitoring Namespace**: Monitoring and alerting (Prometheus, Alertmanager, Grafana, Uptime Kuma)
- **Infrastructure Namespace**: Infrastructure services (Authentik, Homepage, Garage)

## Development Workflow

### Bootstrap
Install required development tools:
```bash
./scripts/bootstrap-dev.sh
```

### Pre-commit Hooks
```bash
pre-commit install
pre-commit run --all-files
```

### Validation
Validate manifests:
```bash
make validate
```

### Local Smoke Test
Test application accessibility:
```bash
make smoke
```

## Scripts and Tools

- **validate.sh**: Lints YAML files and validates Kubernetes manifests
- **smoke.sh**: Tests HTTP endpoints for basic service availability
- **bootstrap-dev.sh**: Installs development dependencies

You are allowd to use any (non-destructive) command, such as git commands, kubectl commands or ssh commands.

## Manifests Structure

The repository follows standard FluxCD patterns with:
- `clusters/prod/` directory containing cluster manifests
- `apps/` directory for application deployments
- Kustomize for configuration management
- SOPS for secret encryption

## Key Technologies

- Kubernetes (K3s)
- FluxCD (GitOps)
- Kustomize
- SOPS (Secrets Management)
- Cilium (CNI)
- Traefik (Ingress Controller)
- cert-manager (TLS)
- ExternalDNS
