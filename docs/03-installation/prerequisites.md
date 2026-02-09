# Pré-requisitos para Instalação do Karpenter

## Cluster EKS

### Versão Mínima
- **EKS**: 1.28 ou superior
- **Kubernetes**: 1.28, 1.29, 1.30, 1.31

### Verificar versão do cluster

```bash
kubectl version --short
aws eks describe-cluster --name my-cluster --query 'cluster.version'
```

## VPC e Networking

### Subnets Privadas

Karpenter provisiona nós em **subnets privadas** (sem IP público direto).

**Requirements:**
- Pelo menos 2 subnets privadas em AZs diferentes
- NAT Gateway ou VPC Endpoints configurados
- Route tables com rota para internet (via NAT)

### Tags Necessárias nas Subnets

```
Key: karpenter.sh/discovery
Value: <cluster-name>
```

**Como adicionar:**

```bash
# Via AWS CLI
aws ec2 create-tags \
  --resources subnet-xxxxx subnet-yyyyy \
  --tags Key=karpenter.sh/discovery,Value=my-cluster

# Via Terraform
resource "aws_ec2_tag" "karpenter_subnet" {
  for_each = toset(var.private_subnet_ids)
  
  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}
```

### Security Groups

Karpenter usa security groups existentes do EKS.

**Tag necessária:**

```
Key: karpenter.sh/discovery
Value: <cluster-name>
```

**Como adicionar:**

```bash
# Via AWS CLI
aws ec2 create-tags \
  --resources sg-xxxxx \
  --tags Key=karpenter.sh/discovery,Value=my-cluster

# Via Terraform
resource "aws_ec2_tag" "karpenter_sg" {
  resource_id = aws_security_group.node.id
  key         = "karpenter.sh/discovery"
  value       = var.cluster_name
}
```

## IAM Permissions

### Para Instalação (Admin/Terraform)

Permissões necessárias:
- `iam:CreateRole`, `iam:AttachRolePolicy`
- `sqs:CreateQueue`, `sqs:SetQueueAttributes`
- `ec2:CreateTags`
- `eks:DescribeCluster`

### Para Karpenter Controller (IRSA)

O módulo Terraform cria automaticamente, mas as permissões incluem:
- `ec2:RunInstances`, `ec2:TerminateInstances`
- `ec2:DescribeInstances`, `ec2:DescribeInstanceTypes`
- `ec2:DescribeSubnets`, `ec2:DescribeSecurityGroups`
- `ec2:DescribeImages`, `ec2:DescribeLaunchTemplates`
- `pricing:GetProducts` (para otimização de custos)
- `sqs:ReceiveMessage`, `sqs:DeleteMessage` (interruption handling)

### Para Nodes (EC2 Instances)

Permissões padrão do EKS:
- `AmazonEKSWorkerNodePolicy`
- `AmazonEC2ContainerRegistryReadOnly`
- `AmazonEKS_CNI_Policy`

## Ferramentas

### Obrigatórias

- **kubectl** 1.28+
  ```bash
  kubectl version --client
  ```

- **AWS CLI** 2.x
  ```bash
  aws --version
  ```

- **Terraform** 1.5+ (se usar Terraform)
  ```bash
  terraform version
  ```

- **Helm** 3.12+ (se usar Helm)
  ```bash
  helm version
  ```

### Recomendadas

- **jq** (parsing JSON)
  ```bash
  jq --version
  ```

- **yq** (parsing YAML)
  ```bash
  yq --version
  ```

## Configuração Local

### AWS Credentials

```bash
# Via AWS CLI
aws configure

# Ou via SSO
aws sso login --profile my-profile
export AWS_PROFILE=my-profile

# Verificar
aws sts get-caller-identity
```

### Kubeconfig

```bash
# Atualizar kubeconfig
aws eks update-kubeconfig --name my-cluster --region us-east-1

# Verificar acesso
kubectl get nodes
```

## Quotas e Limites AWS

### Service Quotas Importantes

Verificar e aumentar se necessário:

```bash
# EC2 Instances
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-1216C47A  # Running On-Demand instances

# Spot Instances
aws service-quotas get-service-quota \
  --service-code ec2 \
  --quota-code L-34B43A08  # All Standard Spot Instance Requests
```

**Recomendações:**
- **On-Demand**: Pelo menos 50 vCPUs
- **Spot**: Pelo menos 200 vCPUs
- **Elastic IPs**: 5+ (se usar NAT Gateways)

## Checklist de Pré-requisitos

Antes de instalar o Karpenter:

- [ ] Cluster EKS 1.28+ criado e acessível
- [ ] kubectl configurado e funcionando
- [ ] AWS CLI configurado com credenciais
- [ ] Subnets privadas com tags `karpenter.sh/discovery`
- [ ] Security groups com tags `karpenter.sh/discovery`
- [ ] NAT Gateway ou VPC Endpoints configurados
- [ ] IAM permissions para criar roles e policies
- [ ] Service quotas verificadas
- [ ] Terraform/Helm instalado (conforme método escolhido)

## Próximos Passos

- [Instalação via Terraform](terraform-installation.md) - Método recomendado
- [Instalação via Helm](helm-installation.md) - Método alternativo
- [Validação](validation.md) - Como verificar instalação

## Troubleshooting de Pré-requisitos

### Subnets não têm rota para internet

```bash
# Verificar route tables
aws ec2 describe-route-tables \
  --filters "Name=association.subnet-id,Values=subnet-xxxxx"

# Deve ter rota 0.0.0.0/0 para NAT Gateway ou IGW
```

### Security group não permite comunicação

```bash
# Verificar regras
aws ec2 describe-security-groups --group-ids sg-xxxxx

# Adicionar regra se necessário
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol all \
  --source-group sg-yyyyy
```

### Quotas insuficientes

```bash
# Solicitar aumento de quota
aws service-quotas request-service-quota-increase \
  --service-code ec2 \
  --quota-code L-34B43A08 \
  --desired-value 500
```

## Referências

- [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [VPC Requirements](https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html)
- [Service Quotas](https://docs.aws.amazon.com/general/latest/gr/eks.html)
