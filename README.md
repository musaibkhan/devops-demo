# ShiftNote

An edge-to-cloud GitOps demo for a clinical voice documentation pipeline, running locally on two k3d clusters.

![Architecture](docs/architecture.png)

## Components

- **Clusters:** k3d ×2 (`edge`, `cloud`) on one Docker network
- **Provisioning:** Terraform (`01-clusters`, then `02-bootstrap`)
- **GitOps:** ArgoCD in `cloud`, managing both clusters
- **Mesh / delivery:** Istio, Argo Rollouts
- **Messaging / scaling:** Strimzi Kafka + MirrorMaker2, KEDA
- **Security:** Kyverno, cosign, SOPS + age
- **Observability:** kube-prometheus-stack, Loki

## Repository layout

```
terraform/
  01-clusters/     Docker network + k3d clusters
  02-bootstrap/    ArgoCD, edge cluster registration, root app
gitops/
  apps/            App-of-apps entry point
  platform/        Platform components
```

## Prerequisites (macOS, Apple Silicon)

```bash
brew install orbstack k3d tfenv kubectl
tfenv install    # reads .terraform-version
```
In OrbStack → Settings → System, set the memory limit to **16 GB**.

## Quick start

**1. Fork this repo** and point the manifests at your fork:
```bash
grep -rl musaibkhan/devops-demo . --exclude-dir=.git | xargs sed -i '' 's#musaibkhan/devops-demo#<you>/<your-fork>#g'
git commit -am "Point to my fork" && git push
```

**2. Create the clusters**
```bash
cd terraform/01-clusters
terraform init && terraform apply
```
Check: `kubectl get nodes --context k3d-cloud` and `kubectl get nodes --context k3d-edge` should each show one Ready node.

**3. Bootstrap ArgoCD**
```bash
cd ../02-bootstrap
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

**4. Verify.** Run the two commands from `terraform output`, open http://localhost:8081 and log in as `admin`. You should see:
- `root` → Synced
- `in-cluster-namespaces` and `edge-namespaces` → Synced/Healthy

```bash
kubectl get ns shiftnote kafka --context k3d-edge
```

## Teardown

Run `terraform destroy` in `02-bootstrap`, then in `01-clusters`.
