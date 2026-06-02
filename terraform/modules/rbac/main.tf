variable "tenant_name" {}

resource "kubernetes_role" "tenant" {
  metadata {
    name      = "${var.tenant_name}-role"
    namespace = var.tenant_name
  }
  rule {
    api_groups = ["", "apps", "extensions"]
    resources  = ["pods", "deployments", "services", "ingresses", "configmaps"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding" "tenant" {
  metadata {
    name      = "${var.tenant_name}-rolebinding"
    namespace = var.tenant_name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.tenant.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = var.tenant_name
  }
}
