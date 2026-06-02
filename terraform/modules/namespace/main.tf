variable "tenant_name" {}
variable "cpu_limit" {}
variable "memory_limit" {}

resource "kubernetes_namespace" "tenant" {
  metadata {
    name = var.tenant_name
    labels = {
        tenant = var.tenant_name
    }
  }
}

resource "kubernetes_resource_quota" "tenant" {
  metadata {
    name = "${var.tenant_name}-quota"
    namespace = kubernetes_namespace.tenant.metadata[0].name
  }
  spec {
    hard = {
      "requests.cpu" = var.cpu_limit
      "requests.memory" = var.memory_limit
      "limits.cpu" = var.cpu_limit
      "limits.memory" = var.memory_limit
      "pods" = "10"
    }
  }
}