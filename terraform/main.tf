terraform {
    required_providers {
        kubernetes = {
            source  = "hashicorp/kubernetes"
            version = "~> 2.0"
        }
    }
}

provider "kubernetes" {
    config_path = "~/.kube/config"
    config_context = "kind-gitops-platform"
}

variable "tenant_name" {}
variable "cpu_limit" {default = "500m"}
variable "memory_limit" {default = "256Mi"}

module "namespace" {
    source = "./modules/namespace"
    tenant_name = var.tenant_name
    cpu_limit = var.cpu_limit
    memory_limit = var.memory_limit
}

module "rbac" {
    source = "./modules/rbac"
    tenant_name = var.tenant_name
    depends_on = [module.namespace]
}

module "network_policy" {
    source = "./modules/network-policy"
    tenant_name = var.tenant_name
    depends_on = [module.namespace]
}