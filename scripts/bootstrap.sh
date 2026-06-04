#!/bin/bash
set -e

echo "==> Creating Kind cluster..."
kind create cluster --config kind-cluster.yaml --name gitops-platform

echo "==> Verifying cluster..."
kubectl cluster-info --context kind-gitops-platform

echo "==> Installing ArgoCD..."
kubectl create namespace argocd
kubectl apply -n argocd --server-side \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> Waiting for ArgoCD deployments to be ready (up to 5 min)..."
for deploy in argocd-server argocd-repo-server argocd-application-controller argocd-dex-server; do
  kubectl wait --for=condition=available \
    deployment/$deploy -n argocd --timeout=300s 2>/dev/null || \
  kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=$deploy -n argocd --timeout=300s 2>/dev/null || \
  echo "  WARNING: $deploy may not be fully ready, continuing..."
done

echo "==> Giving ArgoCD 15s to fully initialize..."
sleep 15

echo "==> Fetching ArgoCD admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "=========================================="
echo "  ArgoCD UI: https://localhost:8080"
echo "  Username:  admin"
echo "  Password:  $ARGOCD_PASSWORD"
echo "=========================================="
echo ""
echo "Bootstrap complete."