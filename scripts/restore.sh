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

echo "==> Starting ArgoCD port-forward..."
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

echo "==> Restoring monitoring stack..."
kubectl create namespace monitoring 2>/dev/null || echo "  monitoring namespace already exists"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update

helm install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --set alertmanager.enabled=false \
  --set prometheus-pushgateway.enabled=false \
  --set server.persistentVolume.enabled=false 2>/dev/null || echo "  Prometheus already installed"

helm install grafana grafana/grafana \
  --namespace monitoring \
  --set adminPassword=admin123 \
  --set persistence.enabled=false \
  --set service.type=ClusterIP 2>/dev/null || echo "  Grafana already installed"

helm install loki grafana/loki \
  --namespace monitoring \
  --set loki.auth_enabled=false \
  --set loki.useTestSchema=true \
  --set deploymentMode=SingleBinary \
  --set singleBinary.replicas=1 \
  --set read.replicas=0 \
  --set write.replicas=0 \
  --set backend.replicas=0 \
  --set chunksCache.enabled=false \
  --set resultsCache.enabled=false \
  --set loki.commonConfig.replication_factor=1 \
  --set loki.storage.type=filesystem 2>/dev/null || echo "  Loki already installed"

helm install promtail grafana/promtail \
  --namespace monitoring \
  --set config.clients[0].url=http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push 2>/dev/null || echo "  Promtail already installed"

echo "==> Waiting for monitoring pods to be ready..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=grafana \
  -n monitoring \
  --timeout=120s

echo "==> Starting monitoring port-forwards..."
kubectl port-forward svc/grafana -n monitoring 3000:80 &
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8888:80 &

echo ""
echo "=========================================="
echo "  Restore complete. Everything is back up."
echo ""
echo "  ArgoCD:  https://localhost:8080"
echo "           admin / $ARGOCD_PASSWORD"
echo ""
echo "  Grafana: http://localhost:3000"
echo "           admin / admin123"
echo ""
echo "  Nginx:   http://tenant1.app.local:8888"
echo "=========================================="