# Exemplo Básico - Karpenter

Setup mínimo para começar com Karpenter em um cluster EKS existente.

## O que este exemplo faz

- Instala Karpenter via Terraform
- Cria um NodePool básico (ARM64 Spot)
- Configura IAM roles (IRSA)
- Configura interruption handling

## Pré-requisitos

- Cluster EKS existente (1.28+)
- Terraform 1.5+
- kubectl configurado
- AWS CLI com credenciais

## Estrutura

```
basic/
├── terraform/          # Instalação via Terraform
│   ├── main.tf
│   ├── karpenter.tf
│   ├── nodepools.tf
│   ├── variables.tf
│   └── outputs.tf
└── manifests/          # Instalação via Kubernetes manifests
    ├── nodepool.yaml
    └── ec2nodeclass.yaml
```

## Quick Start

### Opção 1: Terraform (Recomendado)

```bash
cd terraform/

# Configure suas variáveis
cp terraform.tfvars.example terraform.tfvars
# Edite terraform.tfvars

# Deploy
terraform init
terraform plan
terraform apply

# Valide
kubectl get pods -n karpenter
kubectl get nodepools
```

### Opção 2: Manifests Kubernetes

```bash
# Assumindo que Karpenter já está instalado
kubectl apply -f manifests/

# Valide
kubectl get nodepools
kubectl get ec2nodeclasses
```

## Configuração

### terraform.tfvars.example

```hcl
cluster_name = "my-eks-cluster"
region       = "us-east-1"

# Tags para descoberta de recursos
tags = {
  Environment = "dev"
  ManagedBy   = "terraform"
}
```

## Validação

```bash
# 1. Verificar Karpenter instalado
kubectl get pods -n karpenter

# 2. Verificar NodePool criado
kubectl get nodepool

# 3. Criar um deployment de teste
kubectl create deployment inflate --image=public.ecr.aws/eks-distro/kubernetes/pause:3.2 --replicas=10

# 4. Verificar nós sendo provisionados
kubectl get nodes -w

# 5. Limpar teste
kubectl delete deployment inflate
```

## Próximos Passos

- [Exemplo Produção](../production/) - Setup completo para produção
- [Otimizado para Custo](../cost-optimized/) - Configurações para máxima economia
- [Documentação](../../docs/) - Guias detalhados

## Troubleshooting

### Nós não são provisionados

```bash
# Verificar logs do Karpenter
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# Verificar NodePool
kubectl describe nodepool default

# Verificar IAM role
kubectl describe sa -n karpenter karpenter
```

### Pods ficam Pending

```bash
# Verificar eventos
kubectl get events --sort-by='.lastTimestamp'

# Verificar se pods têm resource requests
kubectl get pods -o json | jq '.items[].spec.containers[].resources'
```

## Recursos

- [Documentação Karpenter](https://karpenter.sh/)
- [Guia de Instalação](../../docs/03-installation/)
- [Troubleshooting](../../docs/07-troubleshooting/)
