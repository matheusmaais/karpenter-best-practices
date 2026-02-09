# NodePools - Guia Completo

## O que é um NodePool?

NodePool define **quando e como** o Karpenter deve provisionar nós. É o recurso principal de configuração do Karpenter.

## Estrutura Básica

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:        # Template para os nós
    metadata:      # Labels e annotations
    spec:          # Especificação dos nós
      nodeClassRef # Referência ao EC2NodeClass
      requirements # Constraints de provisionamento
  limits:          # Limites de recursos
  disruption:      # Políticas de consolidação
  weight:          # Prioridade entre NodePools
```

## Components Detalhados

### 1. Template

Define como os nós serão criados.

```yaml
template:
  metadata:
    labels:
      node.kubernetes.io/managed-by: karpenter
      environment: production
      team: platform
    annotations:
      custom.io/annotation: value
  spec:
    nodeClassRef:
      group: karpenter.k8s.aws
      kind: EC2NodeClass
      name: default
    
    requirements: [...]  # Ver seção Requirements
    
    taints:
      - key: workload-type
        value: batch
        effect: NoSchedule
```

### 2. Requirements

Constraints que definem quais tipos de nós podem ser criados.

#### Arquitetura

```yaml
# ARM64 only (Graviton)
- key: kubernetes.io/arch
  operator: In
  values: ["arm64"]

# AMD64 only (x86)
- key: kubernetes.io/arch
  operator: In
  values: ["amd64"]

# Ambos (multi-arch)
- key: kubernetes.io/arch
  operator: In
  values: ["arm64", "amd64"]
```

#### Sistema Operacional

```yaml
- key: kubernetes.io/os
  operator: In
  values: ["linux"]
```

#### Capacity Type

```yaml
# Spot only (70% cheaper)
- key: karpenter.sh/capacity-type
  operator: In
  values: ["spot"]

# On-Demand only (stable)
- key: karpenter.sh/capacity-type
  operator: In
  values: ["on-demand"]

# Ambos (Spot preferred via weight)
- key: karpenter.sh/capacity-type
  operator: In
  values: ["spot", "on-demand"]
```

#### Instance Category

```yaml
# T-family (burstable, cost-effective)
- key: karpenter.k8s.aws/instance-category
  operator: In
  values: ["t"]

# Compute-optimized
- key: karpenter.k8s.aws/instance-category
  operator: In
  values: ["c"]

# Memory-optimized
- key: karpenter.k8s.aws/instance-category
  operator: In
  values: ["r"]

# General purpose
- key: karpenter.k8s.aws/instance-category
  operator: In
  values: ["m"]

# Múltiplas categorias
- key: karpenter.k8s.aws/instance-category
  operator: In
  values: ["t", "c", "m"]
```

#### Instance Generation

```yaml
# Generation >= 4 (newer)
- key: karpenter.k8s.aws/instance-generation
  operator: Gt
  values: ["3"]

# Specific generations
- key: karpenter.k8s.aws/instance-generation
  operator: In
  values: ["5", "6", "7"]
```

#### Instance Types Específicos

```yaml
# Permitir apenas tipos específicos
- key: node.kubernetes.io/instance-type
  operator: In
  values: ["t4g.medium", "t4g.large"]

# Excluir tipos específicos
- key: node.kubernetes.io/instance-type
  operator: NotIn
  values: ["t4g.nano", "t4g.micro"]
```

#### Availability Zones

```yaml
# Specific AZs
- key: topology.kubernetes.io/zone
  operator: In
  values: ["us-east-1a", "us-east-1b"]
```

### 3. Limits

Previne runaway scaling e controla custos.

```yaml
limits:
  cpu: "100"       # 100 vCPUs máximo
  memory: 200Gi    # 200 GB máximo
```

**Recomendações:**
- **Dev**: 50-100 vCPUs
- **Prod**: 200-500 vCPUs
- **Large**: 1000+ vCPUs

**Cálculo:**
```
Limits = (Workload máximo esperado) * 1.5
```

### 4. Disruption

Controla como e quando nós podem ser removidos/substituídos.

```yaml
disruption:
  # Política de consolidação
  consolidationPolicy: WhenUnderutilized
  
  # Tempo de espera antes de consolidar
  consolidateAfter: 30s
  
  # Tempo máximo de vida do nó
  expireAfter: 168h  # 7 days
  
  # Limita disruption simultânea
  budgets:
    - nodes: "10%"
```

Ver guia completo: [Consolidation](../05-cost-optimization/consolidation.md)

### 5. Weight

Define prioridade entre múltiplos NodePools (menor = maior prioridade).

```yaml
# NodePool 1 - ARM64 Spot (preferred)
weight: 10

# NodePool 2 - AMD64 Spot (fallback)
weight: 20

# NodePool 3 - On-Demand (last resort)
weight: 100
```

## Exemplos Práticos

### NodePool Básico (ARM64 Spot)

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      nodeClassRef:
        name: default
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["t"]
  limits:
    cpu: "100"
    memory: 200Gi
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 1m
```

### NodePool para GPU

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: gpu
spec:
  template:
    spec:
      nodeClassRef:
        name: gpu
      requirements:
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["p3.2xlarge", "p3.8xlarge", "g4dn.xlarge"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]  # GPU geralmente On-Demand
      taints:
        - key: nvidia.com/gpu
          value: "true"
          effect: NoSchedule
  limits:
    cpu: "200"
  disruption:
    consolidationPolicy: WhenEmpty
    expireAfter: Never  # Não expirar nós GPU
```

### NodePool Multi-Arquitetura

```yaml
# NodePool 1: ARM64 (preferred)
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: arm64
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]
  weight: 10  # Higher priority
---
# NodePool 2: AMD64 (fallback)
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: amd64
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
  weight: 20  # Lower priority
```

### NodePool com Taints

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: batch-jobs
spec:
  template:
    metadata:
      labels:
        workload-type: batch
    spec:
      nodeClassRef:
        name: default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
      taints:
        - key: workload-type
          value: batch
          effect: NoSchedule
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 30s  # Remove rápido após jobs
```

**Deployment correspondente:**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch-job
spec:
  template:
    spec:
      tolerations:
        - key: workload-type
          value: batch
          operator: Equal
          effect: NoSchedule
      nodeSelector:
        workload-type: batch
```

## Best Practices

### 1. Múltiplos NodePools

Crie NodePools separados para:
- ✅ Workloads com requirements diferentes (GPU, ARM64, etc)
- ✅ Ambientes diferentes (dev, staging, prod)
- ✅ Times diferentes (multi-tenancy)
- ✅ SLAs diferentes (critical vs best-effort)

### 2. Mutually Exclusive ou Weighted

NodePools devem ser:
- **Mutually exclusive**: Não se sobrepõem (ex: ARM64 vs AMD64)
- **Weighted**: Priorização clara (ex: Spot weight=10, On-Demand weight=100)

**Evitar:**
```yaml
# ❌ NodePools ambíguos (podem causar scheduling aleatório)
NodePool A: arch=arm64, capacity=spot, weight=10
NodePool B: arch=arm64, capacity=spot, weight=10  # Mesmos requirements!
```

### 3. Limits Apropriados

```yaml
# ✅ Bom - previne runaway
limits:
  cpu: "100"
  memory: 200Gi

# ❌ Ruim - sem limites
limits: {}

# ❌ Ruim - muito restritivo
limits:
  cpu: "10"  # Pode bloquear scaling necessário
```

### 4. Consolidação por Ambiente

```yaml
# Dev - agressivo
disruption:
  consolidationPolicy: WhenUnderutilized
  consolidateAfter: 30s

# Prod - conservador
disruption:
  consolidationPolicy: WhenEmpty
  consolidateAfter: 5m
```

## Validação

```bash
# Verificar NodePools
kubectl get nodepools

# Detalhar configuração
kubectl describe nodepool default

# Ver nós criados por cada NodePool
kubectl get nodes -L karpenter.sh/nodepool
```

## Referências

- [Karpenter NodePools](https://karpenter.sh/docs/concepts/nodepools/)
- [Requirements Reference](https://karpenter.sh/docs/concepts/scheduling/#requirements)
- [Instance Types Guide](instance-types.md)
- [Disruption Guide](../05-cost-optimization/consolidation.md)
