terraform {
  required_version = ">= 1.6"
}

locals {
  out_dir = abspath("${path.module}/../.generated")
}

# No mature k3d Terraform provider exists, so we shell out. k3d creates the shared
# "shiftnote" network (see k3d/*.yaml) so ArgoCD in cloud can reach the edge API.
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
      done
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "k3d cluster delete cloud edge"
  }
}

output "next_step" {
  value = "cd ../02-bootstrap && terraform init && terraform apply"
}
