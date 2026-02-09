################################################################################
# Karpenter Installation
################################################################################

locals {
  karpenter_namespace       = "karpenter"
  karpenter_service_account = "karpenter"
  karpenter_version         = "1.8.6"
}

################################################################################
# Karpenter IAM Module (IRSA + Node Role)
################################################################################

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.0"

  cluster_name = var.cluster_name

  # Enable spot instance support
  enable_spot_termination = true
  enable_v1_permissions   = true

  # IRSA for Karpenter controller
  enable_irsa                     = true
  irsa_namespace_service_accounts = ["${local.karpenter_namespace}:${local.karpenter_service_account}"]
  irsa_oidc_provider_arn          = data.aws_eks_cluster.main.identity[0].oidc[0].issuer

  # Create node IAM role for Karpenter nodes
  create_node_iam_role = true
  node_iam_role_name   = "${var.cluster_name}-karpenter-node"

  # Create access entry for nodes
  create_access_entry = true

  tags = var.tags
}

################################################################################
# ECR Public Authentication Token
# Required to pull Karpenter Helm chart from public ECR
################################################################################

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

################################################################################
# Karpenter Helm Chart
################################################################################

resource "helm_release" "karpenter" {
  namespace        = local.karpenter_namespace
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = local.karpenter_version

  # ECR public authentication
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password

  values = [
    yamlencode({
      serviceAccount = {
        name = local.karpenter_service_account
        annotations = {
          "eks.amazonaws.com/role-arn" = module.karpenter.iam_role_arn
        }
      }

      settings = {
        clusterName       = var.cluster_name
        clusterEndpoint   = data.aws_eks_cluster.main.endpoint
        interruptionQueue = module.karpenter.queue_name
      }

      # Resources for the controller
      resources = {
        requests = {
          cpu    = "100m"
          memory = "256Mi"
        }
        limits = {
          cpu    = "1000m"
          memory = "1Gi"
        }
      }

      # Replica count
      replicas = 1

      # Feature gates
      controller = {
        env = [
          {
            name  = "FEATURE_GATES"
            value = "SpotToSpotConsolidation=true"
          }
        ]
      }
    })
  ]

  depends_on = [
    module.karpenter
  ]
}
