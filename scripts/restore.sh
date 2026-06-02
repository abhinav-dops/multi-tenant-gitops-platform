#!/bin/bash
set -e

echo "==> Restoring cluster..."
bash scripts/bootstrap.sh

echo "==> Restoring Terraform infrastructure..."
cd terraform && terraform apply -var-file=tenants/tenant1.tfvars -auto-approve && cd ..

echo "==> Waiting for ArgoCD server to be fully ready..."
until kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server \
  -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null | grep -q "true"; do
  echo "  ArgoCD server not ready yet, waiting 10s..."
  sleep 10
done
echo "  ArgoCD server ready."

echo "==> Starting port-forward..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
sleep 10

echo "==> Re-adding GitHub SSH key to ArgoCD..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure

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