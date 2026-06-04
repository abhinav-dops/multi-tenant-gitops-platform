#!/bin/bash
set -e

echo "==> Restoring cluster..."
bash scripts/bootstrap.sh

echo "==> Restoring Terraform infrastructure..."
cd terraform

for TENANT in tenant1 tenant2; do
  if [ -f "tenants/${TENANT}.tfvars" ]; then
    echo "  Restoring ${TENANT}..."
    terraform workspace new ${TENANT} 2>/dev/null || terraform workspace select ${TENANT}
    terraform apply -var-file=tenants/${TENANT}.tfvars -auto-approve
  fi
done

terraform workspace select default
cd ..

echo "==> Waiting for ArgoCD server to be fully ready..."
until kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server \
  -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null | grep -q "true"; do
  echo "  ArgoCD server not ready yet, waiting 10s..."
  sleep 10
done

echo "==> Starting port-forward..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
sleep 10

echo "==> Logging into ArgoCD..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure

echo "==> Re-adding GitHub SSH key..."
argocd repo add git@github.com:abhinav-dops/multi-tenant-gitops-platform.git \
  --ssh-private-key-path ~/.ssh/id_ed25519 \
  --insecure-skip-server-verification

echo "==> Reapplying ArgoCD manifests..."
kubectl apply -f argocd/projects/
kubectl apply -f argocd/applications/

echo "==> Syncing all apps..."
argocd app sync tenant1-app
argocd app sync tenant2-app

echo "==> Setting poll interval to 30s..."
kubectl patch configmap argocd-cm -n argocd --patch '{"data": {"timeout.reconciliation": "30s"}}'
kubectl rollout restart deployment argocd-repo-server -n argocd

echo "==> Restoring ingress controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo ""
echo "Restore complete. Everything is back up."
echo "ArgoCD UI: https://localhost:8080 (admin / $ARGOCD_PASSWORD)"

chmod +x ~/multi-tenant-gitops-platform/scripts/restore.sh