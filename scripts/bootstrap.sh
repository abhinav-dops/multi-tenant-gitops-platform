#!/bin/bash
set -e

echo "==> Creating Kind cluster..."
kind create cluster --config kind-cluster.yaml

echo "==> Verifying cluster..."
kubectl cluster-info --context kind-gitops-platform

echo "==> Installing ArgoCD..."
kubectl create namespace argocd
kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> Waiting for ArgoCD pods to be ready (this takes 2-3 mins)..."
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

echo "==> Giving ArgoCD server 15s to fully initialize..."
sleep 15

echo "==> Fetching ArgoCD admin password..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "=========================================="
echo "  ArgoCD UI: https://localhost:8080"
echo "  Username:  admin"
echo "  Password:  $ARGOCD_PASSWORD"
echo "=========================================="

echo "==> Logging ArgoCD CLI in via port-forward..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
PF_PID=$!
sleep 5

argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure

echo ""
echo "==> Port-forward running in background (PID: $PF_PID)"
echo "==> Open https://localhost:8080 in your Windows browser"
echo ""
echo "Bootstrap complete..."

chmod +x scripts/bootstrap.sh