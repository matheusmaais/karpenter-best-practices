################################################################################
# Karpenter NodePool and EC2NodeClass
# Basic configuration with ARM64 Spot instances
################################################################################

################################################################################
# EC2NodeClass - Defines the EC2 configuration
################################################################################

resource "kubectl_manifest" "karpenter_node_class" {
  depends_on = [helm_release.karpenter]

  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      # AMI Selection - AL2023 ARM64
      amiFamily = "AL2023"
      amiSelectorTerms = [{
        alias = "al2023@latest"
      }]

      # Subnet selection - use private subnets with Karpenter tag
      subnetSelectorTerms = [{
        tags = {
          "karpenter.sh/discovery" = var.cluster_name
        }
      }]

      # Security group selection
      securityGroupSelectorTerms = [{
        tags = {
          "karpenter.sh/discovery" = var.cluster_name
        }
      }]

      # IAM role for nodes
      role = module.karpenter.node_iam_role_name

      # Block device mappings
      blockDeviceMappings = [{
        deviceName = "/dev/xvda"
        ebs = {
          volumeSize          = "50Gi"
          volumeType          = "gp3"
          encrypted           = true
          deleteOnTermination = true
        }
      }]

      # Metadata options - IMDSv2 required
      metadataOptions = {
        httpEndpoint            = "enabled"
        httpProtocolIPv6        = "disabled"
        httpPutResponseHopLimit = 2
        httpTokens              = "required"
      }

      # Tags
      tags = merge(
        var.tags,
        {
          "Name"                   = "${var.cluster_name}-karpenter"
          "karpenter.sh/discovery" = var.cluster_name
        }
      )
    }
  })
}

################################################################################
# NodePool - Defines when and how to provision nodes
################################################################################

resource "kubectl_manifest" "karpenter_node_pool" {
  depends_on = [kubectl_manifest.karpenter_node_class]

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "default"
    }
    spec = {
      # Template for nodes
      template = {
        metadata = {
          labels = {
            "node.kubernetes.io/managed-by" = "karpenter"
          }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "default"
          }

          # Requirements - what kinds of nodes can be created
          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["arm64"]
            },
            {
              key      = "kubernetes.io/os"
              operator = "In"
              values   = ["linux"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot"]
            },
            {
              key      = "karpenter.k8s.aws/instance-category"
              operator = "In"
              values   = ["t"]
            },
            {
              key      = "karpenter.k8s.aws/instance-generation"
              operator = "Gt"
              values   = ["3"]
            }
          ]
        }
      }

      # Limits - prevent runaway scaling
      limits = {
        cpu    = "100"
        memory = "200Gi"
      }

      # Disruption budget
      disruption = {
        consolidationPolicy = "WhenEmpty"
        consolidateAfter    = "1m"
        expireAfter         = "720h" # 30 days

        budgets = [{
          nodes = "10%"
        }]
      }

      # Weight - lower number = higher priority
      weight = 10
    }
  })
}
