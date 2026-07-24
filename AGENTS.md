# Kubernetes Homelab Project

This project manages a homelab infrastructure using Kubernetes (K3s), FluxCD, and GitOps practices.

## Project Overview

This repository implements a single-node K3s cluster running on Kairos OS within Proxmox, managed through FluxCD for GitOps deployment. The cluster hosts various applications and services including media servers, monitoring tools, development environments, and infrastructure components.

## Architecture

### Cluster Components
- **K3s Cluster**: Single-node Kubernetes cluster running on Kairos OS
- **Networking**: Traefik as ingress controller with websecure-int and websecure-pub routes
- **Monitoring**: Prometheus, Grafana, Alertmanager for cluster monitoring
- **Infrastructure**: GitOps with FluxCD, external secrets with SOPS, and Argo Rollouts

### Services and Applications
The cluster runs a variety of services:
- Monitoring & Logging: Prometheus, Grafana, and Loki
- Media Servers: Lidarr, Prowlarr, Sonarr, Radarr
- Development Tools: GitLab Runner, VSCode Server
- Infrastructure: Traefik, ExternalDNS, SOPS, Vault Secrets Operator
- Other: Home Automation, Backup Systems

## Getting Started

### Prerequisites
- Git and SSH access to repository
- Kubernetes cluster (K3s)
- FluxCD CLI tools
- SOPS for secrets management
- Helm for package management
- kubectl for cluster interaction

### Setup Process
1. Clone this repository
2. Configure your local environment
3. Ensure Flux is running on the cluster
4. Apply the configuration to the cluster

## Maintenance

Regular maintenance tasks:
- Apply updates to cluster components
- Review and update secrets in SOPS
- Monitor cluster health
- Update application configurations as needed

## Development

All development should be done through GitOps principles with changes committed to this repository and applied via FluxCD.

## Backup and Recovery

The system is designed to facilitate backup and recovery by maintaining all configuration in version control, allowing full recreation of the cluster environment from source code.
