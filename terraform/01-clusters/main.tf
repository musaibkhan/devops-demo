terraform {
  required_version = ">= 1.6"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# Honours DOCKER_HOST, works with OrbStack and Docker Desktop.
provider "docker" {}

locals {
  out_dir = abspath("${path.module}/../.generated")
}

# One shared network so ArgoCD (cloud) can reach the edge API server
# and MirrorMaker2 (cloud) can reach edge Kafka.
resource "docker_network" "shiftnote" {
  name = "shiftnote"
}

# Note: no mature k3d Terraform provider exists, so we shell out.
# On AWS this block becomes `module "eks"` and stage 02 does not change.
# Clusters are created sequentially on purpose: parallel k3d runs race on ~/.kube/config.
resource "terraform_data" "clusters" {
  triggers_replace = [
    filesha256("${path.module}/k3d/cloud.yaml"),
    filesha256("${path.module}/k3d/edge.yaml"),
  ]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      mkdir -p ${local.out_dir}
      for c in cloud edge; do
        k3d cluster create --config ${path.module}/k3d/$c.yaml
        k3d kubeconfig get $c > ${local.out_dir}/kubeconfig-$c.yaml
        docker inspect -f '{{(index .NetworkSettings.Networks "shiftnote").IPAddress}}' k3d-$c-server-0 > ${local.out_dir}/$c-ip
      done
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "k3d cluster delete cloud edge"
  }

  depends_on = [docker_network.shiftnote]
}

output "next_step" {
  value = "cd ../02-bootstrap && terraform init && terraform apply"
}
