# Multi-Tenant GitOps Platform

A production-style internal developer platform built from scratch on Kubernetes, implementing GitOps workflows, infrastructure-as-code, multi-tenant isolation, full-stack observability, and a DevSecOps security pipeline.

> Built as a portfolio project to demonstrate skills: Kubernetes, GitOps, Terraform, Helm, CI/CD, observability, and DevSecOps.

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
    ┌─────── GitHub Actions CI ────────────────┐
    │                                          │
    │  [Security Gate 1] Gitleaks              │
    │         │                                │
    │  [Security Gate 2] Checkov (SAST)        │
    │         │                                │
    │  [Security Gate 3] Kyverno Policy Check  │
    │         │                                │
    │  Helm lint + Manifest + Terraform validate│
    │         │                                │
    │  Docker build                            │
    │         │                                │
    │  [Security Gate 4] Trivy scan            │
    │         │                                │
    │  SBOM generation (CycloneDX)             │
    │         │                                │
    │  Docker push → ghcr.io                   │
    │         │                                │
    │  SHA tag commit back to values files     │
    └──────────────────────────────────────────┘
                │
                ▼
            ArgoCD
       (watches Git repo,
        syncs on SHA tag change)
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

  Policy Enforcement (kyverno ns)
  ClusterPolicy: no-latest-tag · resource-limits · tenant-label
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
| Secret Scanning | Gitleaks |
| SAST | Checkov |
| Container Scanning | Trivy |
| SBOM | Trivy (CycloneDX format) |
| Policy Enforcement | Kyverno |
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
2. GitHub Actions runs the full security and validation pipeline
3. Docker image is built, scanned, and pushed with a pinned SHA tag
4. CI commits the SHA tag back to the Helm values files
5. ArgoCD detects the values change and syncs the cluster automatically
6. No manual `kubectl apply` — Git is the single source of truth

### DevSecOps Pipeline

A 6-stage security pipeline runs on every push before any image reaches the cluster:

| Stage | Tool | What it catches |
|-------|------|-----------------|
| Secret scanning | Gitleaks | API keys, tokens, passwords committed to git |
| SAST | Checkov | Terraform misconfigurations, K8s manifest security issues |
| Policy validation | Kyverno CLI | Manifests violating cluster admission policies |
| Container scanning | Trivy | CVEs in the Docker image and OS packages |
| SBOM generation | Trivy (CycloneDX) | Full software bill of materials attached to every build |
| Image tagging | GitHub Actions | SHA-pinned tags replacing mutable `latest` |

Trivy caught a real CVE during development — `CVE-2025-68121` (CRITICAL) in Go stdlib `crypto/tls` on Go 1.22. The pipeline blocked the push; the fix was upgrading to Go 1.24 where it is patched.

### Kyverno Policy Enforcement

Three ClusterPolicies enforce security standards at admission:

- `disallow-latest-tag` — rejects pods using mutable `:latest` image tags
- `require-resource-limits` — rejects pods without CPU and memory limits
- `require-tenant-label` — rejects pods missing a `tenant` label (required for observability)

Policies run in Audit mode — violations are reported without blocking, matching how policy rollout works in production before switching to Enforce mode.

### One-Command Tenant Onboarding

```bash
bash scripts/add-tenant.sh <tenant-name> [cpu-limit] [memory-limit]
```

This single command provisions namespace, RBAC, quotas, network policies, Helm values, ArgoCD manifests, commits to Git, and syncs — all automatically in under 2 minutes.

### Full Observability

- **Prometheus** — scrapes metrics from all tenant namespaces
- **Loki + Promtail** — aggregates container logs, queryable by namespace label
- **Grafana** — unified dashboard showing per-namespace resource usage and live log streams

### CI Pipeline

Every push to `main` runs in order:
1. Gitleaks secret scan (blocks all other jobs if secrets found)
2. Checkov SAST — Terraform + rendered K8s manifests
3. Kyverno CLI policy check against rendered manifests
4. Helm lint, manifest validation, Terraform validate (parallel)
5. Docker build
6. Trivy container scan (blocks push on CRITICAL CVEs with available fixes)
7. SBOM generation — attached as artifact to every build
8. Docker push to ghcr.io
9. SHA tag committed back to Helm values files

---

## Project Structure

```
.
├── .github/
│   └── workflows/
│       └── ci.yaml              # CI + DevSecOps pipeline
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
│   └── values/                  # Per-tenant values files (SHA tag auto-updated by CI)
├── k8s/
│   └── monitoring/              # Prometheus + Grafana datasource config
├── kyverno/
│   └── policies/                # ClusterPolicy definitions
│       ├── disallow-latest-tag.yaml
│       ├── require-resource-limits.yaml
│       └── require-tenant-label.yaml
├── scripts/
│   ├── bootstrap.sh             # Bootstrap cluster from scratch
│   ├── restore.sh               # Restore after cluster deletion (includes Kyverno)
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

**Why Kyverno in Audit mode?**
Policies are introduced in Audit mode to report violations without blocking deployments. This mirrors production practice — validate coverage before switching to Enforce mode to avoid breaking running workloads.

**Why SHA-pinned image tags?**
The `latest` tag is mutable — the same tag can point to a different image digest after every build, making rollbacks unreliable and ArgoCD diffs meaningless. CI commits the short SHA back to the Helm values files after every push, so every ArgoCD sync is traceable to an exact commit.

---

## Author

Abhinav Singh — [github.com/abhinav-dops](https://github.com/abhinav-dops)
