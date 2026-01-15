#!/bin/bash
set -e

echo "=== EKS Capabilities Blueprints Cleanup ==="

# Check if TF_VAR_region is set
if [ -z "$TF_VAR_region" ]; then
  echo "Error: TF_VAR_region is not set"
  echo "Run: export TF_VAR_region=<your-region>"
  exit 1
fi

echo "Region: $TF_VAR_region"

# Delete ArgoCD applications
echo ""
echo "=== Deleting ArgoCD applications ==="
kubectl delete applications --all -n argocd --ignore-not-found=true || true

# Delete ACK resources
echo ""
echo "=== Deleting ACK resources ==="
kubectl delete buckets --all --ignore-not-found=true || true
kubectl delete dbinstances --all --ignore-not-found=true || true
kubectl delete tables --all --ignore-not-found=true || true

# Delete kro resources
echo ""
echo "=== Deleting kro resources ==="
kubectl delete --all -A -l kro.run/instance --ignore-not-found=true || true

# Delete Karpenter resources
echo ""
echo "=== Deleting Karpenter resources ==="
kubectl delete nodeclaim --all --ignore-not-found=true || true
kubectl delete nodepool --all --ignore-not-found=true || true
kubectl delete ec2nodeclass --all --ignore-not-found=true || true

# Wait for nodes to be removed
echo ""
echo "=== Waiting for Karpenter nodes to terminate ==="
sleep 30

# Destroy Terraform resources
echo ""
echo "=== Destroying Terraform resources ==="
cd cluster/terraform
terraform destroy -target="module.eks_blueprints_addons" --auto-approve
terraform destroy -target="module.eks" --auto-approve
terraform destroy --auto-approve

echo ""
echo "=== Cleanup complete ==="
