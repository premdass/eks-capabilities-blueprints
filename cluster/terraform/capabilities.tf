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

# Attach AdministratorAccess for getting started - narrow this for production
resource "aws_iam_role_policy_attachment" "ack_admin" {
  role       = aws_iam_role.ack_capability.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
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

# Grant kro cluster admin permissions for development/testing
# For production, use more restrictive policies based on your ResourceGraphDefinitions
resource "aws_eks_access_policy_association" "kro_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.kro_capability.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_capability.kro]
}

# Grant ArgoCD cluster admin permissions for development/testing
# For production, use more restrictive policies based on your deployment namespaces
resource "aws_eks_access_policy_association" "argocd_admin" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.argocd_capability.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
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
