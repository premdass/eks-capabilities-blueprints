#---------------------------------------------------------------
# AWS Identity Center (IDC) - Create or Fetch
#---------------------------------------------------------------

# Try to fetch existing Identity Center instance (using idc provider for correct region)
data "aws_ssoadmin_instances" "existing" {
  provider = aws.idc
}

locals {
  # Resolve IDC region - use override if set, otherwise use cluster region
  idc_region = coalesce(var.idc_region, var.region)

  # Check if Identity Center already exists (only 0 or 1 can exist per account)
  idc_exists        = length(data.aws_ssoadmin_instances.existing.arns) > 0
  idc_instance_arn  = local.idc_exists ? tolist(data.aws_ssoadmin_instances.existing.arns)[0] : awscc_sso_instance.this[0].instance_arn
  identity_store_id = local.idc_exists ? tolist(data.aws_ssoadmin_instances.existing.identity_store_ids)[0] : awscc_sso_instance.this[0].identity_store_id
}

# Create Identity Center instance if it doesn't exist (using AWSCC provider)
resource "awscc_sso_instance" "this" {
  count = local.idc_exists ? 0 : 1

  name = "eks-cap-bp-idc"

  tags = [for k, v in local.tags : { key = k, value = v }]
}

# Create ArgoCD admin user in Identity Center
resource "aws_identitystore_user" "argocd_admin" {
  provider = aws.idc

  identity_store_id = local.identity_store_id

  display_name = var.argocd_admin_display_name
  user_name    = var.argocd_admin_username

  name {
    given_name  = var.argocd_admin_given_name
    family_name = var.argocd_admin_family_name
  }

  emails {
    value   = var.argocd_admin_email
    primary = true
  }

  depends_on = [awscc_sso_instance.this]
}

#---------------------------------------------------------------
# IAM Roles for EKS Capabilities
#---------------------------------------------------------------

resource "aws_iam_role" "ack_capability" {
  name = "${local.name}-ack-capability"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "capabilities.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })

  tags = local.tags
}

# Least-privilege policy for ACK capability
# Scoped to EKS AccessEntry management only (for ArgoCD namespace onboarding)
resource "aws_iam_role_policy" "ack_capability" {
  name = "${local.name}-ack-policy"
  role = aws_iam_role.ack_capability.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EKSAccessEntryManagement"
        Effect = "Allow"
        Action = [
          "eks:CreateAccessEntry",
          "eks:DeleteAccessEntry",
          "eks:DescribeAccessEntry",
          "eks:ListAccessEntries",
          "eks:UpdateAccessEntry",
          "eks:AssociateAccessPolicy",
          "eks:DisassociateAccessPolicy",
          "eks:ListAssociatedAccessPolicies"
        ]
        Resource = [
          "arn:aws:eks:${var.region}:*:cluster/${local.name}",
          "arn:aws:eks:${var.region}:*:access-entry/${local.name}/*/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "argocd_capability" {
  name = "${local.name}-argocd-capability"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "capabilities.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })

  tags = local.tags
}

resource "aws_iam_role" "kro_capability" {
  name = "${local.name}-kro-capability"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "capabilities.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })

  tags = local.tags
}

#---------------------------------------------------------------
# EKS Capabilities
#---------------------------------------------------------------

resource "aws_eks_capability" "ack" {
  cluster_name              = module.eks.cluster_name
  capability_name           = "ack"
  type                      = "ACK"
  role_arn                  = aws_iam_role.ack_capability.arn
  delete_propagation_policy = "RETAIN"

  tags = local.tags

  depends_on = [module.eks]
}

resource "aws_eks_capability" "argocd" {
  cluster_name              = module.eks.cluster_name
  capability_name           = "argocd"
  type                      = "ARGOCD"
  role_arn                  = aws_iam_role.argocd_capability.arn
  delete_propagation_policy = "RETAIN"

  configuration {
    argo_cd {
      aws_idc {
        idc_instance_arn = local.idc_instance_arn
        idc_region       = local.idc_region
      }
      rbac_role_mapping {
        role = "ADMIN"
        identity {
          id   = aws_identitystore_user.argocd_admin.user_id
          type = "SSO_USER"
        }
      }
    }
  }

  tags = local.tags

  depends_on = [module.eks, awscc_sso_instance.this]
}

resource "aws_eks_capability" "kro" {
  cluster_name              = module.eks.cluster_name
  capability_name           = "kro"
  type                      = "KRO"
  role_arn                  = aws_iam_role.kro_capability.arn
  delete_propagation_policy = "RETAIN"

  tags = local.tags

  depends_on = [module.eks]
}

# Associate AmazonEKSKROPolicy for kro's core functionality
resource "aws_eks_access_policy_association" "kro_policy" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.kro_capability.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSKROPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_capability.kro]
}

#---------------------------------------------------------------
# kro Additional Permissions
# AmazonEKSKROPolicy covers kro's core functionality (kro.run, CRDs, leases, events)
# This ClusterRole adds only what the argocd-namespace RGD needs
#---------------------------------------------------------------

data "aws_caller_identity" "current" {}

# ClusterRole with additional permissions for kro RGDs
resource "kubernetes_cluster_role_v1" "kro_resource_manager" {
  metadata {
    name = "kro-resource-manager"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "kro"
    }
  }

  # Namespaces - RGD creates namespaces
  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # ACK AccessEntry - RGD creates AccessEntries for ArgoCD
  rule {
    api_groups = ["eks.services.k8s.aws"]
    resources  = ["accessentries"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # ConfigMaps - RGD reads argocd-config (read-only)
  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["get", "list", "watch"]
  }

  depends_on = [module.eks]
}

# Bind the ClusterRole to kro's Kubernetes user
# The username format is: arn:aws:sts::<account>:assumed-role/<role-name>/KRO
resource "kubernetes_cluster_role_binding_v1" "kro_resource_manager" {
  metadata {
    name = "kro-resource-manager"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "kro"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.kro_resource_manager.metadata[0].name
  }

  subject {
    kind      = "User"
    name      = "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${aws_iam_role.kro_capability.name}/KRO"
    api_group = "rbac.authorization.k8s.io"
  }
}



#---------------------------------------------------------------
# ArgoCD Configuration ConfigMap
# Used by kro RGD to bind RBAC to ArgoCD's user
#---------------------------------------------------------------

resource "kubernetes_config_map_v1" "argocd_config" {
  metadata {
    name      = "argocd-config"
    namespace = "argocd"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    # ArgoCD IAM role ARN for ACK AccessEntry
    argocdRoleArn = aws_iam_role.argocd_capability.arn
    # Cluster name for ACK AccessEntry
    clusterName = module.eks.cluster_name
  }

  depends_on = [aws_eks_capability.argocd]
}

#---------------------------------------------------------------
# ArgoCD EKS Access Policy
# Grant ArgoCD cluster-wide read access via EKS access policy
# Write access to specific namespaces is granted via kro RGD + ACK AccessEntry
#---------------------------------------------------------------

resource "aws_eks_access_policy_association" "argocd_admin_view" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.argocd_capability.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_capability.argocd]
}

#---------------------------------------------------------------
# ArgoCD kro Access
# ArgoCD needs to create ArgoCDNamespace CRs to trigger namespace onboarding
#---------------------------------------------------------------

resource "kubernetes_cluster_role_v1" "argocd_kro_access" {
  metadata {
    name = "argocd-kro-access"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "argocd"
    }
  }

  # Allow ArgoCD to create/manage ArgoCDNamespace CRs
  rule {
    api_groups = ["kro.run"]
    resources  = ["argocdnamespaces"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  depends_on = [module.eks]
}

resource "kubernetes_cluster_role_binding_v1" "argocd_kro_access" {
  metadata {
    name = "argocd-kro-access"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "argocd"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.argocd_kro_access.metadata[0].name
  }

  subject {
    kind      = "User"
    name      = "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${aws_iam_role.argocd_capability.name}/ARGOCD"
    api_group = "rbac.authorization.k8s.io"
  }
}

# Grant ArgoCD EditPolicy on argocd namespace for creating ArgoCDNamespace CRs
resource "aws_eks_access_policy_association" "argocd_ns_edit" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.argocd_capability.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = ["argocd"]
  }

  depends_on = [aws_eks_capability.argocd]
}

#---------------------------------------------------------------
# Register local cluster for ArgoCD deployments
#---------------------------------------------------------------

resource "kubernetes_secret" "argocd_cluster" {
  metadata {
    name      = "in-cluster"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
    }
  }

  data = {
    name    = "in-cluster"
    server  = module.eks.cluster_arn
    project = "default"
  }

  depends_on = [aws_eks_capability.argocd]
}

#---------------------------------------------------------------
# kro ResourceGraphDefinition for ArgoCD Namespace Onboarding
# Creates the ArgoCDNamespace custom API that automates namespace + RBAC creation
#---------------------------------------------------------------

resource "kubectl_manifest" "argocd_namespace_rgd" {
  yaml_body = file("${path.module}/../../blueprints/base/argocd-namespace/argocd-namespace-rgd.yaml")

  depends_on = [
    aws_eks_capability.kro,
    kubernetes_config_map_v1.argocd_config
  ]
}
