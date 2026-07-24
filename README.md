# kubernetes

Single-node K3s running a large part of my homelab on Kairos on Proxmox using Flux.

## Development workflow

### Bootstrap

Install the required tools locally:

```bash
./scripts/bootstrap-dev.sh
```

### Pre-commit

```bash
pre-commit install
pre-commit run --all-files
```

### Validate manifests

```bash
make validate
```

### Local smoke test

```bash
make smoke
```

### Network diagram

```mermaid
flowchart TB
  subgraph "Proxmox VM"
    subgraph k3s["K3s Cluster (Kairos)"]
      subgraph "System Namespace"
        traefik["Traefik (websecure-int + websecure-pub)"]
        cilium["Cilium"]
        certmanager["cert-manager"]
        externaldns["ExternalDNS"]
      end

      subgraph "General Namespace"
        heimdall["Heimdall"]
        gitea["Gitea"]
        homebox["Homebox"]
        n8n["n8n"]
      end

      subgraph "Automation Namespace"
        awx["AWX + Operator"]
      end

      subgraph "Media Namespace"
        jellyfin["Jellyfin"]
        overseerr["Overseerr"]
        audiobookshelf["Audiobookshelf"]
        calibre["Calibre Web"]
        immich["Immich"]
        sonarr["Sonarr"]
        radarr["Radarr"]
        lidarr["Lidarr"]
        bazarr["Bazarr"]
        prowlarr["Prowlarr"]
        transmission["Transmission"]
        tautulli["Tautulli"]
      end

      subgraph "Monitoring Namespace"
        prometheus["Prometheus"]
        alertmanager["Alertmanager"]
        grafana["Grafana"]
        uptime["Uptime Kuma"]
        karma["Karma"]
        ntfy["ntfy"]
        changedetection["changedetection.io"]
      end

      subgraph "Infrastructure Namespace"
        authentik["Authentik"]
        homepage["Homepage"]
        homepagetv["Homepage TV"]
        garage["Garage (S3 + CDN)"]
        garagewebui["Garage WebUI"]
      end
    end

    subgraph "LAN Services (via Traefik websecure-int)"
      ha["Home Assistant"]
      nanokvm["NanoKVM"]
      ollama["Ollama"]
      plex["Plex"]
      proxmox["Proxmox"]
      unifi["UniFi"]
      unas["UNAS Pro"]
    end
  end

  traefik --> heimdall
  traefik --> gitea
  traefik --> homebox
  traefik --> n8n
  traefik --> awx
  traefik --> jellyfin
  traefik --> overseerr
  traefik --> immich
  traefik --> grafana
  traefik --> homepage
  traefik --> homepagetv
  traefik --> garage
  traefik --> ha
  traefik --> nanokvm
  traefik --> ollama
  traefik --> plex
  traefik --> proxmox
  traefik --> unifi
  traefik --> unas
  traefik --> lidarr
```
