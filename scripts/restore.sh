#!/bin/bash
set -e

echo "==> Restoring cluster..."
bash scripts/bootstrap.sh

echo "==> Restoring Terraform infrastructure..."
cd terraform && terraform apply -var-file=tenants/tenant1.tfvars -auto-approve && cd ..

echo "==> Re-adding GitHub SSH key to ArgoCD..."
argocd repo add git@github.com:abhinav-dops/multi-tenant-gitops-platform.git \
  --ssh-private-key-path ~/.ssh/id_ed25519 \
  --insecure-skip-server-verification

echo "==> Reapplying ArgoCD manifests..."
kubectl apply -f argocd/projects/tenant1-project.yaml
kubectl apply -f argocd/applications/tenant1-app.yaml

echo "==> Syncing app..."
argocd app sync tenant1-app

echo "==> Setting poll interval to 30s..."
kubectl patch configmap argocd-cm -n argocd --patch '{"data": {"timeout.reconciliation": "30s"}}'
kubectl rollout restart deployment argocd-repo-server -n argocd

echo ""
echo "Restore complete. Everything is back up."

chmod +x scripts/restore.sh