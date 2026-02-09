# Configuração Otimizada para Custo - Ambiente Dev

## Economia Esperada: 30-40%

Esta configuração implementa otimizações agressivas adequadas para ambientes de desenvolvimento, priorizando economia de custos sobre estabilidade absoluta.

## Otimizações Implementadas

### 1. Consolidação Agressiva
- **Policy**: `WhenUnderutilized` (vs `WhenEmpty`)
- **Timing**: 30s (vs 1min padrão)
- **Impacto**: Reduz número de nós em 30-40%

### 2. 100% Spot Instances
- **Economia**: ~70% vs On-Demand
- **Risk**: Interrupções possíveis (aceitável em dev)

### 3. ARM64 Graviton
- **Economia**: ~20% vs x86_64
- **Performance**: Equivalente ou melhor

### 4. Node Expiration Curta
- **Timing**: 7 dias (vs 30 dias padrão)
- **Benefício**: Refresh regular (segurança + AMI updates)

### 5. Spot-to-Spot Consolidation
- **Feature**: SpotToSpotConsolidation=true
- **Economia**: Adicional 10-15%

## Configuração

### NodePool

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: dev-optimized
spec:
  template:
    spec:
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
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]

  limits:
    cpu: "100"
    memory: 200Gi

  disruption:
    consolidationPolicy: WhenUnderutilized  # ← AGRESSIVO
    consolidateAfter: 30s                   # ← RÁPIDO
    expireAfter: 168h                       # ← 7 DIAS
    budgets:
      - nodes: "10%"
```

## Trade-offs

### ✅ Vantagens
- Máxima economia de custos
- Utilização eficiente de recursos
- Refresh regular dos nós

### ⚠️ Desvantagens
- Pods podem reiniciar durante consolidação
- Spot interruptions mais frequentes
- Mais movimentação de workloads

## Pré-requisitos CRÍTICOS

### 1. Resource Requests Obrigatórios

**TODOS os pods devem ter `resources.requests` definidos!**

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
        - name: app
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

Sem requests, Karpenter assume 0 CPU/Memory e pode consolidar prematuramente.

### 2. PodDisruptionBudgets Recomendados

Para workloads críticos:

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

## Instalação

```bash
# 1. Aplicar manifests
kubectl apply -f nodepool.yaml
kubectl apply -f ec2nodeclass.yaml

# 2. Verificar
kubectl get nodepool dev-optimized
kubectl get ec2nodeclass dev-optimized

# 3. Monitorar consolidação
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f | grep consolidat
```

## Monitoramento

### Primeiras 24h

```bash
# Ver consolidações
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100 | grep consolidat

# Contar nós
kubectl get nodes -l node.kubernetes.io/managed-by=karpenter --no-headers | wc -l

# Ver utilização
kubectl top nodes
```

### Métricas Esperadas

- **Redução de nós**: 30-40% em períodos de baixa utilização
- **Consolidações**: Visíveis nos logs após 30s de baixa utilização
- **Economia**: $150-300/mês para cluster típico (5-10 nós)

## Rollback

Se houver problemas:

```yaml
# Voltar para configuração conservadora
disruption:
  consolidationPolicy: WhenEmpty
  consolidateAfter: 5m
  expireAfter: 720h
```

## Quando NÃO usar esta configuração

- ❌ Ambiente de produção crítico
- ❌ Workloads stateful sensíveis
- ❌ SLAs rigorosos de uptime
- ❌ Compliance que impede Spot

Para produção, veja: [Exemplo Prod](../prod-environment/)

## Referências

- [Consolidation Guide](../../../docs/05-cost-optimization/consolidation.md)
- [Resource Requests Guide](../../../docs/05-cost-optimization/resource-requests.md)
- [Spot Strategies](../../../docs/05-cost-optimization/spot-strategies.md)
