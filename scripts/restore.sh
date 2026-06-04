#!/bin/bash
set -e

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────
wait_for_deployment() {
  local ns=$1 deploy=$2 timeout=${3:-300}
  echo "    Waiting for deployment/$deploy in $ns..."
  kubectl wait --for=condition=available \
    deployment/$deploy -n $ns --timeout=${timeout}s
}

wait_for_pod_label() {
  local ns=$1 label=$2 timeout=${3:-300}
  echo "    Waiting for pod ($label) in $ns..."
  kubectl wait --for=condition=ready pod \
    -l $label -n $ns --timeout=${timeout}s
}

wait_for_port() {
  local port=$1
  for i in $(seq 1 20); do
    if curl -sk --max-time 2 "https://localhost:$port" > /dev/null 2>&1 || \
       curl -sk --max-time 2 "http://localhost:$port" > /dev/null 2>&1; then
      return 0
    fi
    echo "    Port $port not ready yet, waiting 3s..."
    sleep 3
  done
  echo "    WARNING: port $port never became ready"
  return 0  # non-fatal
}

kill_port_forwards() {
  # Kill any stale port-forwards from a previous run
  pkill -f "kubectl port-forward" 2>/dev/null || true
  sleep 2
}

# ─────────────────────────────────────────────
# 0. Kill stale port-forwards
# ─────────────────────────────────────────────
echo "==> Cleaning up stale port-forwards..."
kill_port_forwards

# ─────────────────────────────────────────────
# 1. Bootstrap cluster
# ─────────────────────────────────────────────
echo "==> Bootstrapping cluster..."
bash scripts/bootstrap.sh

# ─────────────────────────────────────────────
# 2. Terraform — restore each tenant in its own workspace
# ─────────────────────────────────────────────
echo "==> Restoring tenant infrastructure via Terraform..."
cd terraform
for TENANT in tenant1 tenant2; do
  if [ -f "tenants/${TENANT}.tfvars" ]; then
    echo "  --> $TENANT"
    terraform workspace new ${TENANT} 2>/dev/null || terraform workspace select ${TENANT}
    terraform apply -var-file=tenants/${TENANT}.tfvars -auto-approve
  fi
done
terraform workspace select default
cd ..

# ─────────────────────────────────────────────
# 3. ArgoCD — wait, port-forward, login, wire repo
# ─────────────────────────────────────────────
echo "==> Waiting for ArgoCD to be ready..."
wait_for_deployment argocd argocd-server 300

echo "==> Starting ArgoCD port-forward..."
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
ARGOCD_PF_PID=$!
sleep 5
wait_for_port 8080

echo "==> Logging into ArgoCD..."
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)
argocd login localhost:8080 --username admin --password "$ARGOCD_PASSWORD" --insecure

echo "==> Re-adding GitHub SSH key..."
argocd repo add git@github.com:abhinav-dops/multi-tenant-gitops-platform.git \
  --ssh-private-key-path ~/.ssh/id_ed25519 \
  --insecure-skip-server-verification

echo "==> Applying ArgoCD projects and applications..."
kubectl apply -f argocd/projects/
kubectl apply -f argocd/applications/

echo "==> Setting ArgoCD poll interval to 30s..."
kubectl patch configmap argocd-cm -n argocd \
  --patch '{"data": {"timeout.reconciliation": "30s"}}' 2>/dev/null || true
kubectl rollout restart deployment argocd-repo-server -n argocd

# ─────────────────────────────────────────────
# 4. Ingress controller
# ─────────────────────────────────────────────
echo "==> Restoring Nginx Ingress controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
echo "    Waiting for ingress-nginx..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

# ─────────────────────────────────────────────
# 5. Monitoring stack
# ─────────────────────────────────────────────
echo "==> Restoring monitoring stack..."
kubectl create namespace monitoring 2>/dev/null || true

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update

# Prometheus
echo "  --> Installing Prometheus..."
helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --set alertmanager.enabled=false \
  --set prometheus-pushgateway.enabled=false \
  --set server.persistentVolume.enabled=false \
  --wait --timeout 5m

# Loki (single-binary, no cache, no memory pressure)
echo "  --> Installing Loki..."
helm upgrade --install loki grafana/loki \
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
  --set loki.storage.type=filesystem \
  --wait --timeout 5m

# Promtail — ships logs to Loki gateway
echo "  --> Installing Promtail..."
helm upgrade --install promtail grafana/promtail \
  --namespace monitoring \
  --set "config.clients[0].url=http://loki-gateway.monitoring.svc.cluster.local/loki/api/v1/push" \
  --wait --timeout 3m

# Grafana — with datasources provisioned automatically via Helm values
echo "  --> Installing Grafana (with auto-provisioned datasources)..."
helm upgrade --install grafana grafana/grafana \
  --namespace monitoring \
  --set adminPassword=admin123 \
  --set persistence.enabled=false \
  --set service.type=ClusterIP \
  --set-json 'datasources.datasources\.yaml={"apiVersion":1,"datasources":[{"name":"Prometheus","type":"prometheus","url":"http://prometheus-server.monitoring.svc.cluster.local","access":"proxy","isDefault":true},{"name":"Loki","type":"loki","url":"http://loki-gateway.monitoring.svc.cluster.local","access":"proxy"}]}' \
  --wait --timeout 3m

# ─────────────────────────────────────────────
# 6. Sync ArgoCD apps (after infra + ingress are up)
# ─────────────────────────────────────────────
echo "==> Syncing ArgoCD applications..."
# Wait for repo-server restart to settle
sleep 15

for TENANT in tenant1 tenant2; do
  echo "  --> Syncing $TENANT..."
  argocd app sync ${TENANT}-app --timeout 120 || echo "  WARNING: $TENANT sync had issues, ArgoCD will retry automatically"
done

# ─────────────────────────────────────────────
# 7. Port-forwards for browsing
# ─────────────────────────────────────────────
echo "==> Starting port-forwards..."
kubectl port-forward svc/grafana -n monitoring 3000:80 &
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8888:80 &

# Brief wait then verify
sleep 5

# ─────────────────────────────────────────────
# 8. Summary
# ─────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  RESTORE COMPLETE"
echo "============================================================"
echo ""
echo "  ArgoCD   → https://localhost:8080"
echo "             admin / $ARGOCD_PASSWORD"
echo ""
echo "  Grafana  → http://localhost:3000"
echo "             admin / admin123"
echo "             Datasources: Prometheus + Loki (auto-configured)"
echo ""
echo "  tenant1  → http://tenant1.app.local:8888"
echo "  tenant2  → http://tenant2.app.local:8888"
echo ""
echo "  Loki logs query: {namespace=\"tenant1\"}"
echo "============================================================"
echo ""
echo "  To generate traffic for Loki logs:"
echo "    kubectl port-forward -n tenant1 svc/tenant1-app-svc 7777:80 &"
echo "    for i in \$(seq 1 30); do curl -s http://localhost:7777/ > /dev/null; done"
echo "============================================================"