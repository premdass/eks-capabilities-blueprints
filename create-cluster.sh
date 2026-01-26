#!/bin/bash
set -e

echo "=== EKS Capabilities Blueprints - Cluster Creation ==="

# Check if TF_VAR_region is set
if [ -z "$TF_VAR_region" ]; then
  echo "Error: TF_VAR_region is not set"
  echo "Run: export TF_VAR_region=<your-region>"
  exit 1
fi

echo "Region: $TF_VAR_region"

cd cluster/terraform

# Initialize Terraform
echo ""
echo "=== Initializing Terraform ==="
terraform init

# Step 1: VPC
echo ""
echo "=== Step 1/6: Creating VPC ==="
terraform apply -target="module.vpc" -auto-approve

# Step 2: EKS cluster
echo ""
echo "=== Step 2/6: Creating EKS cluster ==="
terraform apply -target="module.eks" -auto-approve

# Step 3: Karpenter
echo ""
echo "=== Step 3/6: Installing Karpenter ==="
terraform apply -target="module.karpenter" -target="helm_release.karpenter" -target="kubectl_manifest.karpenter_default_ec2_node_class" -target="kubectl_manifest.karpenter_default_node_pool" -auto-approve

# Step 4: EKS addons
echo ""
echo "=== Step 4/6: Installing EKS addons ==="
terraform apply -target="module.eks_blueprints_addons" -auto-approve

# Step 5: Capabilities
echo ""
echo "=== Step 5/6: Creating EKS Capabilities ==="
terraform apply -target="aws_iam_role.ack_capability" -target="aws_iam_role.argocd_capability" -target="aws_iam_role.kro_capability" -target="aws_iam_role_policy.ack_capability" -auto-approve
terraform apply -target="aws_eks_capability.ack" -target="aws_eks_capability.argocd" -target="aws_eks_capability.kro" -auto-approve

# Step 6: Everything else
echo ""
echo "=== Step 6/6: Configuring remaining resources ==="
terraform apply -auto-approve

# Configure kubectl
echo ""
echo "=== Configuring kubectl ==="
aws eks --region $TF_VAR_region update-kubeconfig --name eks-capabilities-blueprints

# Verify
echo ""
echo "=== Verifying cluster ==="
kubectl get nodes
echo ""
kubectl api-resources | grep -E "kro.run|argoproj.io|services.k8s.aws" | head -10

echo ""
echo "=== Cluster creation complete ==="
echo ""
echo "Next steps:"
echo "  1. Apply the ArgoCD namespace RGD: kubectl apply -f blueprints/base/argocd-namespace/argocd-namespace-rgd.yaml"
echo "  2. Deploy simple-webapp: kubectl apply -f blueprints/simple-webapp/application.yaml"
