variable "tenant_name" {}

resource "kubernetes_network_policy" "tenant_isolation" {
  metadata {
    name      = "${var.tenant_name}-isolation"
    namespace = var.tenant_name
  }
  spec {
    pod_selector {}
    ingress {
      from {
        namespace_selector {
          match_labels = {
            tenant = var.tenant_name
          }
        }
      }
    }
    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "ingress-nginx"
          }
        }
      }
    }
    egress {
      to {
        namespace_selector {
          match_labels = {
            tenant = var.tenant_name
          }
        }
      }
    }
    egress {}
    policy_types = ["Ingress", "Egress"]
  }
}