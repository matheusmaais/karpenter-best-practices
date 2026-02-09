# Consolidação de Nós - Guia Completo

## O que é Consolidação?

Consolidação é o processo pelo qual o Karpenter **reorganiza pods em menos nós** para reduzir custos, removendo nós subutilizados ou vazios.

## Economia Esperada

- **WhenEmpty**: 10-15% de economia
- **WhenUnderutilized**: 30-40% de economia  
- **WhenEmptyOrUnderutilized**: 40-50% de economia

## Políticas de Consolidação

### 1. WhenEmpty (Conservadora)

Remove apenas nós **completamente vazios** (sem pods não-daemonset).

```yaml
disruption:
  consolidationPolicy: WhenEmpty
  consolidateAfter: 1m
```

**Quando usar:**
- Ambientes de produção críticos
- Workloads sensíveis a disruption
- Primeira implementação de Karpenter

**Prós:**
- ✅ Risco mínimo
- ✅ Sem movimentação de pods
- ✅ Previsível

**Contras:**
- ❌ Economia limitada (10-15%)
- ❌ Nós subutilizados permanecem ativos

### 2. WhenUnderutilized (Balanceada) ⭐ RECOMENDADA

Consolida nós **subutilizados**, movendo pods para nós com mais capacidade.

```yaml
disruption:
  consolidationPolicy: WhenUnderutilized
  consolidateAfter: 30s
  expireAfter: 168h  # 7 days
  budgets:
    - nodes: "10%"
```

**Quando usar:**
- Ambientes de desenvolvimento
- Produção com PodDisruptionBudgets configurados
- Workloads stateless
- Objetivo de otimização de custos

**Prós:**
- ✅ Economia significativa (30-40%)
- ✅ Respeitapods com PDBs
- ✅ Consolidação inteligente
- ✅ Balance entre custo e estabilidade

**Contras:**
- ⚠️ Pods podem reiniciar durante consolidação
- ⚠️ Requer resource requests definidos
- ⚠️ Mais movimentação de workloads

### 3. WhenEmptyOrUnderutilized (Agressiva)

Combina ambas as políticas - máxima economia.

```yaml
disruption:
  consolidationPolicy: WhenEmptyOrUnderutilized
  consolidateAfter: 30s
  expireAfter: 168h
  budgets:
    - nodes: "5%"  # Mais conservador
```

**Quando usar:**
- Ambientes de desenvolvimento/staging
- Workloads 100% stateless
- Máxima prioridade em custo

**Prós:**
- ✅ Máxima economia (40-50%)
- ✅ Utilização ótima de recursos

**Contras:**
- ⚠️ Mais disruptiva
- ⚠️ Requer PDBs bem configurados
- ⚠️ Pode causar instabilidade se mal configurada

## Parâmetros de Consolidação

### consolidateAfter

Tempo de espera antes de consolidar um nó.

```yaml
consolidateAfter: 30s   # Rápido (dev)
consolidateAfter: 1m    # Padrão (prod)
consolidateAfter: 5m    # Conservador (prod crítica)
```

**Recomendações:**
- **Dev**: 30s - resposta rápida
- **Prod**: 1-5m - evita consolidações desnecessárias
- **Batch jobs**: 30s - remove nós rapidamente após jobs

### expireAfter

Tempo máximo de vida de um nó antes de ser substituído.

```yaml
expireAfter: 168h   # 7 dias (dev)
expireAfter: 720h   # 30 dias (prod)
expireAfter: Never  # Nunca expira
```

**Benefícios da expiração:**
- ✅ Refresh regular de AMIs (segurança)
- ✅ Atualização de configurações
- ✅ Prevenção de drift

**Recomendações:**
- **Dev**: 7 dias - refresh frequente
- **Prod**: 30 dias - balance entre refresh e estabilidade
- **Stateful**: Never - evitar disruption

### budgets

Limita quantos nós podem ser disruptados simultaneamente.

```yaml
budgets:
  - nodes: "10%"      # 10% dos nós por vez
  - nodes: "5"        # Máximo 5 nós por vez
  - nodes: "0"        # Desabilita consolidação
```

**Recomendações:**
- **Dev**: 10-20% - consolidação rápida
- **Prod**: 5-10% - consolidação controlada
- **Crítica**: 1-5% - consolidação muito conservadora

## Como Funciona a Consolidação

### Cálculo de Utilização

```
Utilização do Nó = (Soma dos requests dos pods) / (Capacidade total do nó)
```

**Exemplo:**

```
Nó: t4g.medium (2 vCPU, 4GB RAM)

Pods:
├─ Pod A: requests 500m CPU, 1GB RAM
├─ Pod B: requests 200m CPU, 512MB RAM
└─ Pod C: requests 100m CPU, 256MB RAM

Utilização = (500m + 200m + 100m) / 2000m = 40% CPU
           = (1GB + 512MB + 256MB) / 4GB = 44% Memory

Karpenter vê: "Nó está 40-44% utilizado"
```

### Decisão de Consolidação

Karpenter considera consolidar quando:

1. **Utilização < 50%** (threshold padrão)
2. **Pods podem ser movidos** para outros nós
3. **PodDisruptionBudgets** são respeitados
4. **Budget de disruption** não foi excedido

### Fluxo de Consolidação

```
1. Karpenter detecta nó subutilizado (< 50%)
2. Espera consolidateAfter (ex: 30s)
3. Verifica se pods podem ser movidos
4. Verifica PodDisruptionBudgets
5. Taint o nó (NoSchedule)
6. Drain os pods (eviction)
7. Pods são reagendados em outros nós
8. Nó é terminado
9. Economia realizada! 💰
```

## Configurações por Ambiente

### Desenvolvimento

```yaml
disruption:
  consolidationPolicy: WhenUnderutilized
  consolidateAfter: 30s
  expireAfter: 168h  # 7 days
  budgets:
    - nodes: "20%"
```

**Economia**: 30-40%  
**Risco**: Baixo (aceitável para dev)

### Produção

```yaml
disruption:
  consolidationPolicy: WhenUnderutilized
  consolidateAfter: 5m
  expireAfter: 720h  # 30 days
  budgets:
    - nodes: "5%"
```

**Economia**: 20-30%  
**Risco**: Muito baixo

### Produção Crítica

```yaml
disruption:
  consolidationPolicy: WhenEmpty
  consolidateAfter: 10m
  expireAfter: Never
  budgets:
    - nodes: "1"
```

**Economia**: 10-15%  
**Risco**: Mínimo

## Pré-requisitos para Consolidação

### 1. Resource Requests (CRÍTICO)

**Todos os pods DEVEM ter resource requests definidos!**

```yaml
# ❌ SEM requests - Karpenter assume 0 CPU/Memory
containers:
  - name: app
    image: nginx

# ✅ COM requests - Karpenter calcula corretamente
containers:
  - name: app
    image: nginx
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
```

**Por quê?**  
Sem requests, Karpenter não consegue calcular utilização real e pode consolidar prematuramente.

### 2. PodDisruptionBudgets

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

Karpenter **respeita PDBs** durante consolidação.

### 3. Graceful Termination

Configure `terminationGracePeriodSeconds` adequadamente:

```yaml
spec:
  terminationGracePeriodSeconds: 30  # Default
```

## Monitoramento

### Logs de Consolidação

```bash
# Ver consolidações em tempo real
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f | grep consolidat

# Exemplo de log:
# "considering consolidation" - Analisando possibilidade
# "consolidating nodes" - Iniciando consolidação
# "launched node" - Novo nó provisionado (se necessário)
# "deleted node" - Nó removido
```

### Métricas

```bash
# Contar nós Karpenter
kubectl get nodes -l node.kubernetes.io/managed-by=karpenter --no-headers | wc -l

# Ver utilização
kubectl top nodes

# Ver idade dos nós
kubectl get nodes -l node.kubernetes.io/managed-by=karpenter \
  -o custom-columns=NAME:.metadata.name,AGE:.metadata.creationTimestamp
```

### Eventos

```bash
# Ver eventos de disruption
kubectl get events -A | grep -i evict

# Ver eventos do Karpenter
kubectl get events -n karpenter --sort-by='.lastTimestamp'
```

## Troubleshooting

### Consolidação não está acontecendo

**Causas comuns:**

1. **Pods sem resource requests**
   ```bash
   # Verificar
   ./scripts/check-resource-requests.sh
   ```

2. **PodDisruptionBudgets bloqueando**
   ```bash
   # Verificar PDBs
   kubectl get pdb -A
   ```

3. **Utilização > 50%**
   ```bash
   # Ver utilização real
   kubectl top nodes
   ```

4. **Budget de disruption excedido**
   ```bash
   # Ver logs
   kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | grep budget
   ```

### Consolidação muito agressiva

**Sintomas:**
- Muitos restarts de pods
- Instabilidade de aplicações
- Eventos de Evicted frequentes

**Soluções:**

1. Aumentar `consolidateAfter`:
   ```yaml
   consolidateAfter: 5m  # Era: 30s
   ```

2. Reduzir budget:
   ```yaml
   budgets:
     - nodes: "5%"  # Era: 10%
   ```

3. Voltar para WhenEmpty:
   ```yaml
   consolidationPolicy: WhenEmpty
   ```

## Spot-to-Spot Consolidation

Feature que permite trocar instâncias Spot por outras mais baratas.

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
- ✅ Mantém workloads em Spot

### Considerações

- ⚠️ Mais movimentação de pods
- ⚠️ Requer diversidade de instance types
- ⚠️ Melhor para workloads stateless

## Casos de Uso

### Batch Jobs

```yaml
# Consolidação rápida após jobs terminarem
disruption:
  consolidationPolicy: WhenEmpty
  consolidateAfter: 30s
  expireAfter: 24h  # Nós de batch não duram muito
```

### APIs Stateless

```yaml
# Consolidação agressiva com PDBs
disruption:
  consolidationPolicy: WhenUnderutilized
  consolidateAfter: 1m
  expireAfter: 168h
  budgets:
    - nodes: "10%"
```

### Workloads Stateful

```yaml
# Consolidação conservadora
disruption:
  consolidationPolicy: WhenEmpty
  consolidateAfter: 10m
  expireAfter: Never  # Não expirar
  budgets:
    - nodes: "1"  # Um nó por vez
```

## Referências

- [Karpenter Disruption Docs](https://karpenter.sh/docs/concepts/disruption/)
- [AWS Blog - Consolidation Best Practices](https://aws.amazon.com/blogs/containers/optimizing-your-kubernetes-compute-costs-with-karpenter-consolidation/)
- [Resource Requests Guide](resource-requests.md)
- [Monitoring Guide](monitoring.md)
