################################################################################
# Karpenter Basic Example
# Minimal setup to get Karpenter running on an existing EKS cluster
################################################################################

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
  }
}

provider "aws" {
  region = var.region
}

# Get EKS cluster data
data "aws_eks_cluster" "main" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "main" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
  load_config_file       = false
}

# Get VPC and subnet information
data "aws_vpc" "main" {
  id = data.aws_eks_cluster.main.vpc_config[0].vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Tag subnets for Karpenter discovery
resource "aws_ec2_tag" "karpenter_subnet_discovery" {
  for_each = toset(data.aws_subnets.private.ids)

  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}

# Get security group
data "aws_security_group" "node" {
  vpc_id = data.aws_vpc.main.id

  filter {
    name   = "tag:aws:eks:cluster-name"
    values = [var.cluster_name]
  }

  filter {
    name   = "tag:Name"
    values = ["*node*"]
  }
}

# Tag security group for Karpenter discovery
resource "aws_ec2_tag" "karpenter_sg_discovery" {
  resource_id = data.aws_security_group.node.id
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}
