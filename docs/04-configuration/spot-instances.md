# Spot Instances com Karpenter

## O que são Spot Instances?

Spot instances são capacidade EC2 não utilizada disponível por até **70% de desconto** comparado a On-Demand.

**Trade-off**: AWS pode interromper (reclaim) com aviso de 2 minutos.

## Por que usar Spot com Karpenter?

Karpenter é **otimizado para Spot**:

1. ✅ **Diversidade automática**: Seleciona de múltiplos pools Spot
2. ✅ **Price-Capacity-Optimized**: Escolhe pools com menor risco de interrupção
3. ✅ **Interruption handling**: Reage automaticamente a interrupções
4. ✅ **Spot-to-Spot consolidation**: Troca por instâncias mais baratas

## Configuração

### Spot Only (Máxima Economia)

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: spot-only
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
```

**Quando usar:**
- Ambientes de desenvolvimento
- Workloads stateless
- Batch jobs
- Aplicações tolerantes a falhas

### Spot + On-Demand Fallback

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: spot-with-fallback
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
```

**Comportamento:**
- Karpenter tenta Spot primeiro
- Se não houver capacidade Spot, usa On-Demand
- Mais caro, mas mais disponível

### Múltiplos NodePools (Recomendado para Prod)

```yaml
# NodePool 1: Spot (preferred)
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: spot
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
  weight: 10  # Higher priority
---
# NodePool 2: On-Demand (fallback)
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: on-demand
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
  weight: 100  # Lower priority
```

## Allocation Strategy

Karpenter usa **Price-Capacity-Optimized** para Spot:

1. Identifica pools Spot com **menor risco de interrupção**
2. Entre esses, escolhe o **mais barato**
3. Distribui entre múltiplos pools para **diversidade**

### Como Funciona

```
Pools Spot disponíveis:
├─ t4g.medium  - $0.0084/h - Risco: Baixo    ✅ ESCOLHIDO
├─ t4g.large   - $0.0168/h - Risco: Baixo    ✅ ESCOLHIDO
├─ t3.medium   - $0.0104/h - Risco: Médio
└─ c5.large    - $0.0340/h - Risco: Alto

Karpenter escolhe: t4g.medium e t4g.large (menor risco + menor preço)
```

## Interruption Handling

### Como Funciona

```
1. AWS envia aviso de interrupção (2 minutos antes)
2. EventBridge captura evento
3. SQS Queue recebe mensagem
4. Karpenter lê mensagem
5. Karpenter taint o nó (NoSchedule)
6. Karpenter drain os pods
7. Karpenter provisiona novo nó (se necessário)
8. Pods são reagendados
9. Nó é terminado
```

### Configuração

#### SQS Queue (via Terraform)

```hcl
module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"
  
  enable_spot_termination = true  # ← IMPORTANTE
  # ...
}
```

#### Helm Chart

```yaml
settings:
  interruptionQueue: my-cluster-karpenter-queue  # ← IMPORTANTE
```

### Verificar Interruption Handling

```bash
# Ver logs de interrupções
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | grep -i interrupt

# Ver mensagens na SQS
aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/123456789/my-cluster-karpenter \
  --attribute-names ApproximateNumberOfMessages
```

## Diversidade de Instance Types

### Por que é Importante

Mais instance types = **menor risco de interrupção**

```
Cenário A: 2 instance types
- t4g.medium, t4g.large
- Risco: ALTO (pools limitados)

Cenário B: 10 instance types
- t4g.*, c6g.*, m6g.*
- Risco: BAIXO (muitos pools)
```

### Como Aumentar Diversidade

```yaml
# ❌ Muito restritivo
requirements:
  - key: node.kubernetes.io/instance-type
    operator: In
    values: ["t4g.medium"]  # Apenas 1 tipo!

# ✅ Diversidade adequada
requirements:
  - key: karpenter.k8s.aws/instance-category
    operator: In
    values: ["t", "c", "m"]  # Múltiplas famílias
  - key: karpenter.k8s.aws/instance-generation
    operator: Gt
    values: ["3"]  # Gerações modernas
```

## Spot-to-Spot Consolidation

Feature que permite trocar instâncias Spot por outras **mais baratas**.

### Habilitar

```yaml
# No Helm values do Karpenter
controller:
  env:
    - name: FEATURE_GATES
      value: "SpotToSpotConsolidation=true"
```

### Benefícios

- ✅ Economia adicional de 10-15%
- ✅ Aproveita variações de preço Spot
- ✅ Mantém workloads em Spot (não precisa On-Demand)

### Exemplo

```
Situação inicial:
- Nó A: t4g.large Spot ($0.0168/h)
- Nó B: t4g.large Spot ($0.0168/h)
- Utilização: 40% cada

Karpenter detecta:
- Pode consolidar em 1x t4g.xlarge Spot ($0.0336/h)
- Economia: $0.0168/h (50%)

Ação:
- Provisiona t4g.xlarge
- Move pods de A e B para novo nó
- Termina A e B
```

## Best Practices para Spot

### 1. Diversidade é Crítica

```yaml
# ✅ BOM - múltiplas opções
requirements:
  - key: karpenter.k8s.aws/instance-category
    operator: In
    values: ["t", "c", "m", "r"]
  - key: karpenter.k8s.aws/instance-generation
    operator: Gt
    values: ["3"]

# ❌ RUIM - muito restritivo
requirements:
  - key: node.kubernetes.io/instance-type
    operator: In
    values: ["t4g.medium"]
```

### 2. Interruption Handling Obrigatório

```yaml
# ✅ SEMPRE configure
settings:
  interruptionQueue: my-cluster-karpenter-queue
```

### 3. Graceful Termination

```yaml
# Em seus Deployments
spec:
  template:
    spec:
      terminationGracePeriodSeconds: 30
      containers:
        - name: app
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 15"]
```

### 4. PodDisruptionBudgets

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: my-app
```

### 5. Múltiplas AZs

```yaml
# Distribua workloads entre AZs
spec:
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
```

## Quando NÃO usar Spot

### ❌ Evite Spot para:

1. **Databases stateful** (RDS, PostgreSQL, MySQL)
2. **Workloads com estado crítico** sem replicação
3. **Long-running jobs** (> 6 horas) sem checkpointing
4. **Compliance** que requer garantias de disponibilidade

### Alternativas:

- **Savings Plans**: Desconto de 30-50% com compromisso
- **Reserved Instances**: Desconto de 40-60% com compromisso
- **On-Demand**: Sem desconto, mas garantido

## Monitoramento de Spot

### Métricas Importantes

```bash
# Taxa de interrupções
kubectl get events -A | grep -i "spot.*interrupt" | wc -l

# Nós Spot vs On-Demand
kubectl get nodes -L karpenter.sh/capacity-type

# Tempo médio de vida dos nós Spot
kubectl get nodes -o json | jq '.items[] | select(.metadata.labels["karpenter.sh/capacity-type"]=="spot") | .metadata.creationTimestamp'
```

### Alertas Recomendados

1. **Alta taxa de interrupções** (> 10/hora)
2. **Pods em CrashLoopBackOff** após interrupções
3. **Falta de capacidade Spot** frequente

## Economia Real

### Exemplo: Cluster Dev (10 nós)

```
Configuração On-Demand:
10x t4g.medium = 10 * $0.0336/h = $0.336/h = $246/mês

Configuração Spot:
10x t4g.medium Spot = 10 * $0.0101/h = $0.101/h = $74/mês

Economia: $172/mês (70%)
```

### Exemplo: Cluster Prod (50 nós, mix)

```
Configuração On-Demand:
50x m6g.large = 50 * $0.077/h = $3.85/h = $2,821/mês

Configuração Spot (80% Spot + 20% On-Demand):
40x m6g.large Spot = 40 * $0.023/h = $0.92/h = $674/mês
10x m6g.large On-Demand = 10 * $0.077/h = $0.77/h = $564/mês
Total = $1,238/mês

Economia: $1,583/mês (56%)
```

## Troubleshooting

### Interrupções muito frequentes

**Causa**: Poucos instance types disponíveis

**Solução**: Aumentar diversidade

```yaml
# Adicionar mais categorias
- key: karpenter.k8s.aws/instance-category
  operator: In
  values: ["t", "c", "m", "r"]  # Mais opções
```

### Falta de capacidade Spot

**Causa**: Região/AZ com pouca capacidade

**Solução**: Adicionar On-Demand fallback

```yaml
- key: karpenter.sh/capacity-type
  operator: In
  values: ["spot", "on-demand"]  # Fallback
```

### Pods não toleram interrupções

**Causa**: Aplicação não está preparada

**Solução**:
- Adicionar graceful shutdown
- Configurar PodDisruptionBudgets
- Usar On-Demand para workloads críticos

## Referências

- [AWS Spot Instances](https://aws.amazon.com/ec2/spot/)
- [Spot Best Practices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html)
- [Karpenter Interruption](https://karpenter.sh/docs/concepts/disruption/#interruption)
- [Spot Strategies Guide](../05-cost-optimization/spot-strategies.md)
