# Instalação do Karpenter via Terraform

## Overview

Este guia mostra como instalar o Karpenter usando Terraform, o método **recomendado** para ambientes de produção.

## Vantagens do Terraform

- ✅ Infraestrutura como código (versionável)
- ✅ Idempotente e reproduzível
- ✅ Módulo oficial terraform-aws-modules
- ✅ Gerenciamento de estado
- ✅ Fácil de auditar e revisar

## Arquitetura da Instalação

```
Terraform cria:
├── IAM Role para Karpenter Controller (IRSA)
├── IAM Role para Nodes
├── SQS Queue (interruption handling)
├── Event Bridge Rules (Spot interruptions)
├── Helm Release (Karpenter chart)
├── NodePool (configuração de provisionamento)
└── EC2NodeClass (configuração de EC2)
```

## Passo a Passo

### 1. Estrutura de Arquivos

```
karpenter-terraform/
├── main.tf           # Providers e data sources
├── karpenter.tf      # Módulo Karpenter + Helm
├── nodepools.tf      # NodePools e EC2NodeClass
├── variables.tf      # Variáveis
├── outputs.tf        # Outputs
└── terraform.tfvars  # Valores das variáveis
```

### 2. Configurar Providers

```hcl
# main.tf
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
```

### 3. Módulo Karpenter

```hcl
# karpenter.tf
locals {
  karpenter_namespace       = "karpenter"
  karpenter_service_account = "karpenter"
  karpenter_version         = "1.8.6"
}

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

  # Create node IAM role
  create_node_iam_role = true
  node_iam_role_name   = "${var.cluster_name}-karpenter-node"

  # Create access entry
  create_access_entry = true

  tags = var.tags
}
```

### 4. Helm Chart

```hcl
# karpenter.tf (continuação)

# ECR Public authentication
data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.virginia
}

provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

resource "helm_release" "karpenter" {
  namespace        = local.karpenter_namespace
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = local.karpenter_version

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

      replicas = 1
    })
  ]

  depends_on = [module.karpenter]
}
```

### 5. NodePools e EC2NodeClass

Ver arquivo completo em: [nodepools.tf](../../examples/basic/terraform/nodepools.tf)

### 6. Variáveis

```hcl
# variables.tf
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
```

### 7. Terraform.tfvars

```hcl
# terraform.tfvars
cluster_name = "my-eks-cluster"
region       = "us-east-1"

tags = {
  Environment = "dev"
  ManagedBy   = "terraform"
  Project     = "karpenter"
}
```

## Instalação

### Passo 1: Inicializar

```bash
terraform init
```

### Passo 2: Planejar

```bash
terraform plan -out=tfplan
```

**Revisar o plan:**
- IAM roles criados
- SQS queue criada
- Helm release instalado
- NodePool e EC2NodeClass criados

### Passo 3: Aplicar

```bash
terraform apply tfplan
```

**Tempo estimado:** 3-5 minutos

### Passo 4: Validar

```bash
# Verificar pod do Karpenter
kubectl get pods -n karpenter

# Verificar NodePool
kubectl get nodepools

# Verificar EC2NodeClass
kubectl get ec2nodeclasses

# Ver logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
```

## Outputs Importantes

```hcl
# outputs.tf
output "karpenter_role_arn" {
  description = "ARN of the Karpenter controller IAM role"
  value       = module.karpenter.iam_role_arn
}

output "karpenter_node_role_arn" {
  description = "ARN of the Karpenter node IAM role"
  value       = module.karpenter.node_iam_role_arn
}

output "karpenter_queue_name" {
  description = "Name of the SQS queue"
  value       = module.karpenter.queue_name
}
```

## Upgrade do Karpenter

### Atualizar versão

```hcl
# karpenter.tf
locals {
  karpenter_version = "1.9.0"  # Nova versão
}
```

```bash
terraform plan
terraform apply
```

### Best Practices para Upgrade

1. ✅ Testar em ambiente não-produção primeiro
2. ✅ Ler release notes e breaking changes
3. ✅ Fazer backup do estado do Terraform
4. ✅ Upgrade durante janela de manutenção
5. ✅ Monitorar logs após upgrade

## Troubleshooting

### Erro: "No valid credential sources"

```bash
# Verificar credenciais AWS
aws sts get-caller-identity

# Configurar profile
export AWS_PROFILE=my-profile
```

### Erro: "Cluster not found"

```bash
# Verificar nome do cluster
aws eks list-clusters

# Verificar região
aws configure get region
```

### Helm release falha

```bash
# Ver logs detalhados
terraform apply -auto-approve 2>&1 | tee terraform.log

# Verificar se ECR public está acessível
aws ecr-public get-authorization-token --region us-east-1
```

### NodePool não é criado

```bash
# Verificar CRDs instalados
kubectl get crds | grep karpenter

# Verificar dependências
terraform graph | dot -Tpng > graph.png
```

## Exemplo Completo

Ver exemplo funcional completo em: [examples/basic/terraform/](../../examples/basic/terraform/)

## Próximos Passos

- [Validação da Instalação](validation.md)
- [Configurar NodePools](../04-configuration/nodepools.md)
- [Otimizar Custos](../05-cost-optimization/consolidation.md)

## Referências

- [Terraform AWS EKS Module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest)
- [Karpenter Terraform Module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest/submodules/karpenter)
- [Karpenter Helm Chart](https://gallery.ecr.aws/karpenter/karpenter)
