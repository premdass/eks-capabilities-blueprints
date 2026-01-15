output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${var.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "cluster_name" {
  description = "Cluster name of the EKS cluster"
  value       = module.eks.cluster_name
}

output "vpc_id" {
  description = "VPC ID that the EKS cluster is using"
  value       = module.vpc.vpc_id
}

output "node_instance_role_name" {
  description = "IAM Role name that each Karpenter node will use"
  value       = local.name
}

output "region" {
  description = "AWS region where the cluster is deployed"
  value       = var.region
}

output "availability_zones" {
  description = "Availability zones used by the cluster"
  value       = local.azs
}

#---------------------------------------------------------------
# EKS Capabilities Outputs
#---------------------------------------------------------------

output "idc_instance_arn" {
  description = "AWS Identity Center instance ARN"
  value       = local.idc_instance_arn
}

output "idc_identity_store_id" {
  description = "AWS Identity Center identity store ID"
  value       = local.identity_store_id
}

output "ack_capability_arn" {
  description = "ACK capability ARN"
  value       = aws_eks_capability.ack.arn
}

output "argocd_capability_arn" {
  description = "ArgoCD capability ARN"
  value       = aws_eks_capability.argocd.arn
}

output "argocd_server_url" {
  description = "ArgoCD server URL"
  value       = try(aws_eks_capability.argocd.configuration[0].argo_cd[0].server_url, null)
}

output "argocd_admin_user_id" {
  description = "ArgoCD admin user ID in Identity Center"
  value       = aws_identitystore_user.argocd_admin.user_id
}

output "kro_capability_arn" {
  description = "kro capability ARN"
  value       = aws_eks_capability.kro.arn
}
