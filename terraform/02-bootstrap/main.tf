# Stage 2: install ArgoCD in the cloud cluster, register the edge cluster, hand over to Git.
# Everything after this file is owned by ArgoCD, not Terraform.
# Separate state from 01-clusters: providers here need a cluster that exists at plan time.

terraform {
  required_version = ">= 1.6"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
  }
}

variable "repo_url" {
  description = "Your public GitHub repo, e.g. https://github.com/<you>/shiftnote.git"
  type        = string
  default     = "https://github.com/musaibkhan/devops-demo.git"

  validation {
    condition     = can(regex("^https://github\\.com/.+\\.git$", var.repo_url))
    error_message = "repo_url must look like https://github.com/<user>/<repo>.git"
  }
}

variable "target_revision" {
  type    = string
  default = "main"
}

locals {
  gen        = abspath("${path.module}/../.generated")
  cloud_kube = "${local.gen}/kubeconfig-cloud.yaml"
  edge       = yamldecode(file("${local.gen}/kubeconfig-edge.yaml"))
}

provider "helm" {
  kubernetes = {
    config_path = local.cloud_kube
  }
}

provider "kubernetes" {
  config_path = local.cloud_kube
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  wait             = true

  values = [yamlencode({
    configs = {
      # GitHub cannot send webhooks to localhost, so poll often instead of the 3m default.
      cm     = { "timeout.reconciliation" = "30s" }
      params = { "server.insecure" = true } # TLS terminates at the Istio gateway later
    }
    dex           = { enabled = false }
    notifications = { enabled = false }
  })]
}

# Hub-and-spoke: the edge cluster is registered declaratively as a cluster Secret.
resource "kubernetes_secret_v1" "edge_cluster" {
  metadata {
    name      = "cluster-edge"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
      "shiftnote.io/role"              = "edge"
    }
  }

  data = {
    name = "edge"
    # Container name on the shared network, resolved by the runtime's DNS. Unlike the
    # IP it survives cluster stop/start. Matches --tls-san in k3d/edge.yaml.
    server = "https://k3d-edge-server-0:6443"
    config = jsonencode({
      tlsClientConfig = {
        caData   = local.edge.clusters[0].cluster["certificate-authority-data"]
        certData = local.edge.users[0].user["client-certificate-data"]
        keyData  = local.edge.users[0].user["client-key-data"]
      }
    })
  }

  depends_on = [helm_release.argocd]
}

# App-of-apps root. Installed via the argocd-apps chart so Terraform never
# needs the Application CRD at plan time.
resource "helm_release" "root_app" {
  name       = "argocd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  namespace  = "argocd"

  values = [yamlencode({
    applications = {
      root = {
        namespace = "argocd"
        project   = "default"
        source = {
          repoURL        = var.repo_url
          targetRevision = var.target_revision
          path           = "gitops/apps"
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "argocd"
        }
        syncPolicy = {
          automated = { prune = true, selfHeal = true }
        }
      }
    }
  })]

  depends_on = [kubernetes_secret_v1.edge_cluster]
}

output "argocd_ui" {
  value = "kubectl --kubeconfig ${local.cloud_kube} -n argocd port-forward svc/argocd-server 8081:80  ->  http://localhost:8081"
}

output "argocd_password" {
  value = "kubectl --kubeconfig ${local.cloud_kube} -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
