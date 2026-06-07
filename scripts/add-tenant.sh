#!/bin/bash
set -e

TENANT_NAME=$1
CPU_LIMIT=${2:-500m}
MEMORY_LIMIT=${3:-256Mi}

if [ -z "$TENANT_NAME" ]; then
  echo "Usage: bash scripts/add-tenant.sh <tenant-name> [cpu-limit] [memory-limit]"
  echo "Example: bash scripts/add-tenant.sh tenant2 500m 256Mi"
  exit 1
fi

echo "==> Onboarding tenant: $TENANT_NAME"

# ── Making sure ArgoCD port-forward is alive ─────────────────────────────────
if ! curl -sk --max-time 2 https://localhost:8080 > /dev/null 2>&1; then
  echo "==> ArgoCD port-forward not detected, starting it..."
  kubectl port-forward svc/argocd-server -n argocd 8080:443 &
  sleep 8
fi

# ── Making sure we're logged into ArgoCD ────────────────────────────────────
echo "==> Logging into ArgoCD..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure

# ── Step 1: Terraform (isolated workspace per tenant) ─────────────────────
echo "==> Creating Terraform vars..."
mkdir -p terraform/tenants
cat > terraform/tenants/${TENANT_NAME}.tfvars << TFEOF
tenant_name  = "${TENANT_NAME}"
cpu_limit    = "${CPU_LIMIT}"
memory_limit = "${MEMORY_LIMIT}"
TFEOF

echo "==> Applying Terraform in isolated workspace..."
cd terraform
terraform workspace new ${TENANT_NAME} 2>/dev/null || terraform workspace select ${TENANT_NAME}
terraform apply -var-file=tenants/${TENANT_NAME}.tfvars -auto-approve
cd ..

# ── Step 2: Helm values ────────────────────────────────────────────────────
echo "==> Creating Helm values..."

# Get latest SHA tag from registry
LATEST_SHA=$(curl -s "https://ghcr.io/v2/abhinav-dops/multi-tenant-gitops-platform/gitops-api/tags/list" \
  -H "Authorization: Bearer $(echo -n "$GITHUB_TOKEN" | base64)" \
  2>/dev/null | grep -o '"[a-f0-9]\{7\}"' | head -1 | tr -d '"' || echo "latest")

echo "  --> Using image tag: ${LATEST_SHA}"

cat > helm/values/${TENANT_NAME}-values.yaml << HELMEOF
tenant: ${TENANT_NAME}

replicaCount: 1

image:
  repository: ghcr.io/abhinav-dops/multi-tenant-gitops-platform/gitops-api
  tag: ${LATEST_SHA}
  pullPolicy: Always

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

ingress:
  enabled: true
  host: ${TENANT_NAME}.app.local

resources:
  limits:
    cpu: ${CPU_LIMIT}
    memory: ${MEMORY_LIMIT}
  requests:
    cpu: 100m
    memory: 64Mi

env:
  - name: TENANT_NAME
    value: "${TENANT_NAME}"
HELMEOF

# ── Step 3: ArgoCD project ─────────────────────────────────────────────────
echo "==> Creating ArgoCD project..."
cat > argocd/projects/${TENANT_NAME}-project.yaml << ARGOEOF
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: ${TENANT_NAME}-project
  namespace: argocd
spec:
  description: Project for ${TENANT_NAME}
  sourceRepos:
    - git@github.com:abhinav-dops/multi-tenant-gitops-platform.git
  destinations:
    - namespace: ${TENANT_NAME}
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
ARGOEOF

# ── Step 4: ArgoCD application ─────────────────────────────────────────────
echo "==> Creating ArgoCD application..."
cat > argocd/applications/${TENANT_NAME}-app.yaml << ARGOEOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${TENANT_NAME}-app
  namespace: argocd
spec:
  project: ${TENANT_NAME}-project
  source:
    repoURL: git@github.com:abhinav-dops/multi-tenant-gitops-platform.git
    targetRevision: main
    path: helm/tenant-app
    helm:
      valueFiles:
        - ../../helm/values/${TENANT_NAME}-values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: ${TENANT_NAME}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
ARGOEOF

# ── Step 5: Apply ArgoCD manifests ─────────────────────────────────────────
echo "==> Applying ArgoCD manifests..."
kubectl apply -f argocd/projects/${TENANT_NAME}-project.yaml
kubectl apply -f argocd/applications/${TENANT_NAME}-app.yaml

# ── Step 6: Commit and push ────────────────────────────────────────────────
echo "==> Pushing to Git..."
git add \
  helm/values/${TENANT_NAME}-values.yaml \
  argocd/projects/${TENANT_NAME}-project.yaml \
  argocd/applications/${TENANT_NAME}-app.yaml \
  terraform/tenants/${TENANT_NAME}.tfvars
git commit -m "feat: onboard ${TENANT_NAME}"
git push

# ── Step 7: Sync ArgoCD ────────────────────────────────────────────────────
echo "==> Syncing ArgoCD..."
argocd app sync ${TENANT_NAME}-app --timeout 120

echo ""
echo "=========================================="
echo "  Tenant ${TENANT_NAME} onboarded!"
echo "  App URL: http://${TENANT_NAME}.app.local:8888"
echo "  ArgoCD:  https://localhost:8080"
echo "=========================================="