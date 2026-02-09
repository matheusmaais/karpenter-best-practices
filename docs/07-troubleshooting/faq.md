# FAQ - Perguntas Frequentes

## Instalação e Setup

### P: Preciso de um bootstrap node group?

**R:** Sim, é **altamente recomendado**.

O Karpenter controller precisa rodar em nós estáveis (on-demand) para evitar chicken-and-egg problem. Se o Karpenter rodar em nós que ele mesmo gerencia, pode haver problemas durante consolidação ou interrupções Spot.

**Alternativa:** Rodar Karpenter no Fargate (mais caro).

### P: Posso usar Karpenter com Cluster Autoscaler?

**R:** Sim, mas não é recomendado.

Eles podem coexistir temporariamente durante migração, mas:
- Use node selectors para separar workloads
- Cluster Autoscaler gerencia node groups tradicionais
- Karpenter gerencia seus próprios nós

**Melhor prática:** Migre completamente para Karpenter.

### P: Qual versão do Karpenter devo usar?

**R:** Use a versão mais recente estável (atualmente v1.8.6).

- Teste em ambiente não-produção primeiro
- Leia release notes antes de upgrade
- Evite versões alpha/beta em produção

## Configuração

### P: Quantos NodePools devo criar?

**R:** Depende dos seus requisitos.

**Mínimo:** 1 NodePool (básico)

**Recomendado:**
- 2-3 NodePools (ARM64 Spot + AMD64 fallback + On-Demand crítico)

**Multi-tenancy:**
- 1 NodePool por time/workload type

**Evite:** Muitos NodePools (> 10) - complexidade desnecessária

### P: Devo usar Spot ou On-Demand?

**R:** Depende do workload.

**Spot (70% economia):**
- ✅ Workloads stateless
- ✅ Batch jobs
- ✅ Ambientes de dev/staging
- ✅ APIs com múltiplas réplicas

**On-Demand (estável):**
- ✅ Databases
- ✅ Workloads stateful
- ✅ Aplicações críticas sem HA
- ✅ Compliance requirements

**Mix (recomendado para prod):**
- 70-80% Spot + 20-30% On-Demand

### P: ARM64 ou AMD64?

**R:** ARM64 (Graviton) quando possível.

**Vantagens:**
- 20% mais barato
- Melhor performance/watt
- Suportado pela maioria das aplicações modernas

**Quando usar AMD64:**
- Software proprietário sem build ARM64
- Aplicações legacy
- Dependencies específicas de x86

**Recomendação:** Multi-arch com ARM64 preferred.

### P: Qual consolidationPolicy usar?

**R:** Depende do ambiente.

- **Dev**: `WhenUnderutilized` (30-40% economia)
- **Prod**: `WhenUnderutilized` com timers conservadores (20-30% economia)
- **Prod crítica**: `WhenEmpty` (10-15% economia, mínimo risco)

Ver guia: [Consolidation](../05-cost-optimization/consolidation.md)

## Custos

### P: Quanto vou economizar com Karpenter?

**R:** Tipicamente 20-40%, dependendo da configuração.

**Fatores:**
- Spot instances: 70% vs On-Demand
- ARM64: 20% vs AMD64
- Consolidação: 30-40% adicional
- Eliminação de over-provisioning

**Exemplo real:**
- Cluster dev: $150-300/mês economia
- Cluster prod: $500-1000/mês economia

### P: Karpenter tem custo adicional?

**R:** Não, Karpenter é gratuito (open-source).

**Custos:**
- Bootstrap node group: ~$25-50/mês (2x t4g.medium)
- SQS queue: < $1/mês
- CloudWatch logs: ~$5-10/mês

**Total overhead:** ~$30-60/mês

**ROI:** Economia 10-50x maior que o custo!

### P: Como monitorar custos?

**R:** Use Kubecost ou AWS Cost Explorer.

```bash
# Kubecost (recomendado)
kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090

# Filtrar por Karpenter nodes
# Tag: karpenter.sh/discovery=my-cluster
```

## Operação

### P: Como fazer upgrade do Karpenter?

**R:** Via Terraform ou Helm.

```bash
# Terraform
# 1. Atualizar versão em karpenter.tf
locals {
  karpenter_version = "1.9.0"
}

# 2. Aplicar
terraform plan
terraform apply

# 3. Verificar
kubectl get pods -n karpenter
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
```

### P: Pods ficam Pending, o que fazer?

**R:** Verificar logs do Karpenter.

```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | grep -i "pending\|error"
```

**Causas comuns:**
1. Limits do NodePool excedidos
2. IAM permissions faltando
3. Subnets sem tag
4. Falta de capacidade (Spot)
5. Resource requests muito altos

Ver: [Troubleshooting](common-issues.md)

### P: Como forçar um nó a ser removido?

**R:** Drain o nó manualmente.

```bash
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data
```

Karpenter vai remover o nó automaticamente após drain.

### P: Posso impedir que um nó seja consolidado?

**R:** Sim, use annotation.

```bash
kubectl annotate node <node-name> karpenter.sh/do-not-disrupt=true
```

## Segurança

### P: Karpenter precisa de credenciais AWS?

**R:** Não, usa IRSA (IAM Roles for Service Accounts).

Sem credenciais estáticas - mais seguro!

### P: Como garantir que apenas Karpenter crie nós?

**R:** Use IAM policies restritivas.

```json
{
  "Effect": "Allow",
  "Action": "ec2:RunInstances",
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "aws:RequestedRegion": "us-east-1",
      "ec2:InstanceType": ["t4g.*", "m6g.*"]
    }
  }
}
```

### P: IMDSv2 é obrigatório?

**R:** Sim, sempre use IMDSv2.

```yaml
metadataOptions:
  httpTokens: required  # IMDSv2
```

## Performance

### P: Quanto tempo leva para provisionar um nó?

**R:** Tipicamente 45-90 segundos.

- Karpenter detecta pod pending: ~5s
- EC2 API provisiona instância: ~30-60s
- Nó registra no cluster: ~10-20s
- Pod é agendado: ~5s

**Total:** ~1 minuto (vs 3-5 min do Cluster Autoscaler)

### P: Karpenter afeta performance do cluster?

**R:** Não, overhead é mínimo.

- Controller usa ~100m CPU, 256Mi Memory
- Não afeta scheduling de pods
- Não afeta performance de rede

### P: Quantos nós Karpenter pode gerenciar?

**R:** Milhares.

Testado com clusters de 1000+ nós sem problemas.

## Troubleshooting

### P: Logs do Karpenter mostram "insufficient capacity"

**R:** Falta de capacidade EC2 na região/AZ.

**Soluções:**
1. Aumentar diversidade de instance types
2. Adicionar mais AZs
3. Usar On-Demand como fallback
4. Tentar outra região

### P: Consolidação não está funcionando

**R:** Verificar resource requests.

```bash
./scripts/check-resource-requests.sh
```

Pods sem requests = Karpenter assume 0 CPU/Memory!

Ver: [Resource Requests Guide](../05-cost-optimization/resource-requests.md)

### P: Muitas interrupções Spot

**R:** Aumentar diversidade de instance types.

```yaml
# ❌ Ruim - apenas 1 tipo
values: ["t4g.medium"]

# ✅ Bom - múltiplos tipos
values: ["t", "c", "m"]  # Famílias inteiras
```

## Comparações

### P: Karpenter vs Cluster Autoscaler - qual usar?

**R:** Karpenter para maioria dos casos.

**Use Karpenter se:**
- Cluster médio/grande (> 20 nós)
- Workloads dinâmicas
- Quer otimização de custos
- Usa Spot instances

**Use Cluster Autoscaler se:**
- Cluster pequeno (< 10 nós)
- Time sem experiência Kubernetes
- Workloads 100% estáveis
- Precisa de algo battle-tested

### P: Karpenter vs Managed Node Groups?

**R:** Use ambos!

- **Managed Node Groups**: Para bootstrap (Karpenter controller)
- **Karpenter**: Para workloads (dinâmico e otimizado)

### P: Karpenter vs Fargate?

**R:** Depende do workload.

**Karpenter:**
- ✅ Mais barato (Spot + Graviton)
- ✅ Mais flexível
- ✅ Melhor para workloads variáveis

**Fargate:**
- ✅ Serverless (sem gerenciamento de nós)
- ✅ Melhor para workloads pequenos
- ❌ Mais caro (~30% vs Karpenter)
- ❌ Menos flexível

## Mitos e Realidades

### Mito: "Spot instances são instáveis"

**Realidade:** Com Karpenter e diversidade, interrupções são raras e gerenciadas automaticamente.

### Mito: "ARM64 não é compatível"

**Realidade:** 95%+ das aplicações modernas funcionam em ARM64 sem modificação.

### Mito: "Karpenter é complexo demais"

**Realidade:** Setup inicial é mais elaborado, mas operação é mais simples que gerenciar múltiplos node groups.

### Mito: "Consolidação causa downtime"

**Realidade:** Com PodDisruptionBudgets e resource requests corretos, consolidação é transparente.

## Referências

- [Karpenter Documentation](https://karpenter.sh/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Troubleshooting Guide](common-issues.md)
- [Debugging Guide](debugging.md)
