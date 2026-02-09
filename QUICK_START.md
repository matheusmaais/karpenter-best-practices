# Quick Start - 5 Minutos para Karpenter Rodando

## Pré-requisitos Rápidos

```bash
# Verificar se você tem tudo
kubectl version --short          # 1.28+
terraform version                # 1.5+
aws sts get-caller-identity      # Credenciais configuradas
```

## Opção 1: Terraform (Recomendado)

### 1. Clone e Configure

```bash
git clone https://github.com/matheusmaais/karpenter-best-practices.git
cd karpenter-best-practices/examples/basic/terraform

# Configure variáveis
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars  # Edite: cluster_name e region
```

### 2. Deploy

```bash
terraform init
terraform plan
terraform apply -auto-approve
```

**Tempo:** ~3-5 minutos

### 3. Valide

```bash
kubectl get pods -n karpenter
kubectl get nodepools
kubectl get ec2nodeclasses
```

### 4. Teste

```bash
# Criar deployment de teste
kubectl create deployment inflate \
  --image=public.ecr.aws/eks-distro/kubernetes/pause:3.2 \
  --replicas=10

# Ver nós sendo provisionados
kubectl get nodes -w

# Limpar
kubectl delete deployment inflate
```

## Opção 2: Manifests Kubernetes

### Pré-requisito: Karpenter já instalado

Se Karpenter já está instalado (via Terraform ou Helm):

```bash
cd examples/basic/manifests

# Editar arquivos (substituir my-cluster-name)
nano ec2nodeclass.yaml
nano nodepool.yaml

# Aplicar
kubectl apply -f ec2nodeclass.yaml
kubectl apply -f nodepool.yaml

# Validar
kubectl get nodepools
kubectl get ec2nodeclasses
```

## Opção 3: Dev Otimizado (Máxima Economia)

Para ambiente de desenvolvimento com consolidação agressiva:

```bash
cd examples/cost-optimized/dev-environment

# Editar manifests
nano ec2nodeclass.yaml  # Substituir my-cluster-name
nano nodepool.yaml

# Aplicar
kubectl apply -f ec2nodeclass.yaml
kubectl apply -f nodepool.yaml

# Monitorar consolidação
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f | grep consolidat
```

**Economia esperada:** 30-40%

## Validação Rápida

```bash
# Script automático
./scripts/validate-installation.sh my-cluster-name

# Ou manual
kubectl get pods -n karpenter                    # Deve estar Running
kubectl get nodepools                            # Deve listar seus NodePools
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=20
```

## Teste de Provisionamento

```bash
# 1. Criar workload
kubectl create deployment test --image=nginx --replicas=5

# 2. Ver nós sendo criados
kubectl get nodes -w

# 3. Ver logs do Karpenter
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# 4. Limpar
kubectl delete deployment test

# 5. Ver consolidação (após ~1 min)
# Nó deve ser removido automaticamente
```

## Troubleshooting Rápido

### Pods Pending?

```bash
# Ver logs
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | grep -i error

# Verificar IAM
kubectl describe sa -n karpenter karpenter

# Verificar tags nas subnets
aws ec2 describe-subnets \
  --filters "Name=tag:karpenter.sh/discovery,Values=my-cluster"
```

### Nós não provisionam?

```bash
# Verificar NodePool
kubectl describe nodepool default

# Verificar limits
kubectl get nodepool default -o yaml | grep -A 5 limits
```

## Próximos Passos

1. **Otimizar custos:** [Consolidation Guide](docs/05-cost-optimization/consolidation.md)
2. **Adicionar Spot:** [Spot Guide](docs/04-configuration/spot-instances.md)
3. **ARM64/Graviton:** [Graviton Guide](docs/04-configuration/graviton.md)
4. **Produção:** [Production Example](examples/production/)

## Documentação Completa

Ver [README.md](README.md) para índice completo da documentação.

## Suporte

- **Issues:** https://github.com/matheusmaais/karpenter-best-practices/issues
- **Documentação:** https://karpenter.sh/
- **AWS Support:** https://aws.amazon.com/support/

---

**Tempo total:** 5-10 minutos do clone ao Karpenter rodando! 🚀
