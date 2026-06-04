# Multi-Tenant GitOps Platform

A production-style internal developer platform built from scratch on Kubernetes, implementing GitOps workflows, infrastructure-as-code, multi-tenant isolation, and full-stack observability.

> Built as a portfolio project to demonstrate platform engineering skills: Kubernetes, GitOps, Terraform, Helm, CI/CD, and observability.

---

## Overview

This platform allows engineering teams to be onboarded as isolated tenants on a shared Kubernetes cluster. Each tenant gets dedicated infrastructure provisioned automatically — namespace, resource quotas, RBAC, and network policies — with their application deployed and managed entirely through Git.

A single command onboards a new tenant end-to-end in under 2 minutes.

---

## Architecture

```
Developer → GitHub push
                │
                ▼
    ┌─── GitHub Actions CI ───┐
    │  Helm lint              │
    │  Manifest validate      │
    │  Terraform validate     │
    │  Docker build + push ───┼──► ghcr.io
    └─────────────────────────┘
                │
                ▼
            ArgoCD
       (watches Git repo,
        syncs on every push)
                │
        ┌───────┴────────┐
        ▼                ▼
  tenant1 ns        tenant2 ns
  ├─ Deployment     ├─ Deployment
  ├─ Service        ├─ Service
  ├─ Ingress        ├─ Ingress
  ├─ ResourceQuota  ├─ ResourceQuota
  ├─ NetworkPolicy  ├─ NetworkPolicy
  └─ RBAC           └─ RBAC

  Observability (monitoring ns)
  Prometheus · Loki · Grafana
```

---

## Tech Stack

| Layer | Tool |
|-------|------|
| Cluster | Kubernetes (Kind) |
| GitOps controller | ArgoCD |
| Infrastructure as Code | Terraform |
| App packaging | Helm |
| Ingress | Nginx Ingress Controller |
| Metrics | Prometheus |
| Logs | Loki + Promtail |
| Dashboards | Grafana |
| CI/CD | GitHub Actions |
| Container Registry | GitHub Container Registry (ghcr.io) |
| Sample application | Go HTTP API |

---

## Key Features

### Multi-Tenant Isolation

Each tenant is provisioned with:
- Dedicated Kubernetes namespace
- ResourceQuota — hard CPU and memory limits per tenant, preventing noisy-neighbour issues
- NetworkPolicy — tenant pods can only communicate within their own namespace
- RBAC — Role and RoleBinding scoped to the tenant namespace only

### GitOps Workflow

All application changes flow through Git:
1. Developer pushes a change
2. GitHub Actions runs lint, validation, and builds the Docker image
3. ArgoCD detects the change and syncs the cluster automatically
4. No manual `kubectl apply` — Git is the single source of truth

### One-Command Tenant Onboarding

```bash
bash scripts/add-tenant.sh <tenant-name> [cpu-limit] [memory-limit]
```

This single command provisions namespace, RBAC, quotas, network policies, Helm values, ArgoCD manifests, commits to Git, and syncs — all automatically.

### Full Observability

- **Prometheus** — scrapes metrics from all tenant namespaces
- **Loki + Promtail** — aggregates container logs, queryable by namespace label
- **Grafana** — unified dashboard showing per-namespace resource usage and live log streams

### CI Pipeline

Every push to `main` runs:
1. Helm chart linting
2. Kubernetes manifest validation
3. Terraform configuration validation
4. Docker image build and push to ghcr.io (only after all checks pass)

---

## Project Structure

```
.
├── .github/
│   └── workflows/
│       └── ci.yaml              # CI pipeline
├── app/
│   ├── main.go                  # Go HTTP API
│   ├── go.mod
│   └── Dockerfile
├── argocd/
│   ├── applications/            # ArgoCD Application per tenant
│   └── projects/                # ArgoCD AppProject per tenant
├── helm/
│   ├── tenant-app/              # Base Helm chart (shared)
│   │   └── templates/
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       └── ingress.yaml
│   └── values/                  # Per-tenant values files
├── k8s/
│   └── monitoring/              # Prometheus + Grafana datasource config
├── scripts/
│   ├── bootstrap.sh             # Bootstrap cluster from scratch
│   ├── restore.sh               # Restore after cluster deletion
│   └── add-tenant.sh            # Tenant onboarding automation
└── terraform/
    ├── main.tf                  # Root config, calls all modules
    ├── modules/
    │   ├── namespace/           # Namespace + ResourceQuota
    │   ├── rbac/                # Role + RoleBinding
    │   └── network-policy/      # NetworkPolicy
    └── tenants/                 # Per-tenant tfvars
```

---

## Quick Start

### Prerequisites

```bash
# Required tools
docker, kind, kubectl, helm, terraform, argocd
```

### Bootstrap the platform

```bash
git clone git@github.com:abhinav-dops/multi-tenant-gitops-platform.git
cd multi-tenant-gitops-platform
bash scripts/bootstrap.sh
```

### Onboard a tenant

```bash
bash scripts/add-tenant.sh tenant1 500m 256Mi
```

### Access the platform

| Service | Command | URL |
|---------|---------|-----|
| ArgoCD | `kubectl port-forward svc/argocd-server -n argocd 8080:443 &` | https://localhost:8080 |
| Grafana | `kubectl port-forward svc/grafana -n monitoring 3000:80 &` | http://localhost:3000 |
| Tenant app | `kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8888:80 &` | http://tenant1.app.local:8888 |

### Restore after cluster deletion

```bash
bash scripts/restore.sh
```

---

## Sample Application

The platform deploys a Go HTTP API that returns tenant-aware responses:

```json
GET /
{
  "message": "GitOps Platform API",
  "tenant": "tenant1",
  "version": "1.0.0"
}

GET /health
ok
```

The `tenant` field is injected via a Kubernetes environment variable, proving per-tenant configuration isolation.

---

## Design Decisions

**Why Terraform for namespace provisioning?**
Namespace infrastructure (quotas, RBAC, network policies) is cluster-level configuration that should be auditable and version-controlled separately from application code. Terraform workspaces give each tenant isolated state so changes to one tenant never affect another.

**Why ArgoCD over plain Helm?**
ArgoCD provides drift detection and self-healing — if someone manually modifies a resource in the cluster, ArgoCD will revert it to match Git. This enforces Git as the single source of truth.

**Why separate Helm values per tenant?**
One base chart, many tenant configurations. Adding a tenant requires only a new values file — no changes to the chart itself. This scales cleanly to N tenants.

---

## Author

Abhinav Singh — [github.com/abhinav-dops](https://github.com/abhinav-dops)