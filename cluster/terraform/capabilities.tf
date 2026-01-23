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
# Scoped to common ACK controllers: S3, RDS, DynamoDB, EC2, EKS (AccessEntry), and IAM (for service-linked roles)
resource "aws_iam_role_policy" "ack_capability" {
  name = "${local.name}-ack-policy"
  role = aws_iam_role.ack_capability.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3BucketManagement"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketTagging",
          "s3:PutBucketTagging",
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning",
          "s3:GetBucketEncryption",
          "s3:PutBucketEncryption",
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:GetBucketPublicAccessBlock",
          "s3:PutBucketPublicAccessBlock",
          "s3:ListBucket"
        ]
        Resource = "arn:aws:s3:::*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      {
        Sid    = "RDSManagement"
        Effect = "Allow"
        Action = [
          "rds:CreateDBInstance",
          "rds:DeleteDBInstance",
          "rds:DescribeDBInstances",
          "rds:ModifyDBInstance",
          "rds:AddTagsToResource",
          "rds:RemoveTagsFromResource",
          "rds:ListTagsForResource",
          "rds:CreateDBSubnetGroup",
          "rds:DeleteDBSubnetGroup",
          "rds:DescribeDBSubnetGroups"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.region
          }
        }
      },
      {
        Sid    = "DynamoDBManagement"
        Effect = "Allow"
        Action = [
          "dynamodb:CreateTable",
          "dynamodb:DeleteTable",
          "dynamodb:DescribeTable",
          "dynamodb:UpdateTable",
          "dynamodb:TagResource",
          "dynamodb:UntagResource",
          "dynamodb:ListTagsOfResource"
        ]
        Resource = "arn:aws:dynamodb:${var.region}:*:table/*"
      },
      {
        Sid    = "EC2NetworkingForRDS"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      },
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
      },
      {
        Sid    = "IAMServiceLinkedRoles"
        Effect = "Allow"
        Action = [
          "iam:CreateServiceLinkedRole"
        ]
        Resource = "arn:aws:iam::*:role/aws-service-role/*"
        Condition = {
          StringLike = {
            "iam:AWSServiceName" = [
              "rds.amazonaws.com",
              "dynamodb.amazonaws.com"
            ]
          }
        }
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

#---------------------------------------------------------------
# kro Least-Privilege RBAC
# Custom ClusterRole scoped to only the resources kro needs to manage
# Bound to kro's Kubernetes user: arn:aws:sts::<account>:assumed-role/<role>/KRO
# See: https://docs.aws.amazon.com/eks/latest/userguide/capabilities-security.html
#---------------------------------------------------------------

data "aws_caller_identity" "current" {}

# ClusterRole with least-privilege permissions for kro
resource "kubernetes_cluster_role_v1" "kro_resource_manager" {
  metadata {
    name = "kro-resource-manager"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "kro"
    }
  }

  # Namespaces - kro needs to create/manage namespaces
  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # ClusterRoles and ClusterRoleBindings - for RBAC management
  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["clusterroles", "clusterrolebindings"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Roles and RoleBindings - namespace-scoped RBAC
  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # ACK AccessEntry resources
  rule {
    api_groups = ["eks.services.k8s.aws"]
    resources  = ["accessentries"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # kro CRDs - kro needs full access to its own resources
  rule {
    api_groups = ["kro.run"]
    resources  = ["*"]
    verbs      = ["*"]
  }

  # Events - kro needs to create events for status reporting
  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create", "patch"]
  }

  # Core resources - kro needs these to grant them to ArgoCD
  rule {
    api_groups = [""]
    resources  = ["pods", "services", "configmaps", "secrets", "persistentvolumeclaims", "serviceaccounts"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Apps resources - kro needs these to grant them to ArgoCD
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Networking resources - kro needs these to grant them to ArgoCD
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  # Batch resources - kro needs these to grant them to ArgoCD
  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
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
    namespace = "default"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  data = {
    # ArgoCD's Kubernetes username for RBAC binding
    argocdUserArn = "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${aws_iam_role.argocd_capability.name}/ARGOCD"
  }

  depends_on = [aws_eks_capability.argocd]
}

#---------------------------------------------------------------
# ArgoCD Cluster-Wide Read Access
# ArgoCD needs to list/watch resources cluster-wide to sync applications
#---------------------------------------------------------------

resource "kubernetes_cluster_role_v1" "argocd_read" {
  metadata {
    name = "argocd-cluster-read"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "argocd"
    }
  }

  # Core resources
  rule {
    api_groups = [""]
    resources  = ["namespaces", "pods", "services", "configmaps", "secrets", "persistentvolumeclaims", "serviceaccounts", "events", "endpoints"]
    verbs      = ["get", "list", "watch"]
  }

  # Apps resources
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets", "daemonsets", "controllerrevisions"]
    verbs      = ["get", "list", "watch"]
  }

  # Networking
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["get", "list", "watch"]
  }

  # Batch
  rule {
    api_groups = ["batch"]
    resources  = ["jobs", "cronjobs"]
    verbs      = ["get", "list", "watch"]
  }

  # RBAC
  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
    verbs      = ["get", "list", "watch"]
  }

  # kro resources
  rule {
    api_groups = ["kro.run"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }

  # ACK resources - each ACK controller has its own API group
  rule {
    api_groups = ["eks.services.k8s.aws", "s3.services.k8s.aws", "rds.services.k8s.aws", "dynamodb.services.k8s.aws", "ec2.services.k8s.aws", "iam.services.k8s.aws", "sqs.services.k8s.aws", "sns.services.k8s.aws", "lambda.services.k8s.aws"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }

  # Karpenter resources
  rule {
    api_groups = ["karpenter.sh", "karpenter.k8s.aws"]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }

  depends_on = [module.eks]
}

resource "kubernetes_cluster_role_binding_v1" "argocd_read" {
  metadata {
    name = "argocd-cluster-read"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "argocd"
    }
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.argocd_read.metadata[0].name
  }

  subject {
    kind      = "User"
    name      = "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${aws_iam_role.argocd_capability.name}/ARGOCD"
    api_group = "rbac.authorization.k8s.io"
  }
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
