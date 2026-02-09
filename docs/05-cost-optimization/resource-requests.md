# Resource Requests - Por que são CRÍTICOS

## TL;DR

**Sem `resources.requests` definidos, a consolidação do Karpenter NÃO funciona corretamente!**

## O Problema

Karpenter calcula a utilização de um nó baseado nos **resource requests** dos pods:

```
Utilização = (Soma dos requests) / (Capacidade total do nó)
```

**Para pods SEM requests:**
- Karpenter assume: `CPU = 0` e `Memory = 0`
- O pod "não conta" no cálculo de utilização

## Exemplo Prático

### Cenário: Nó t4g.medium (2 vCPU, 4GB RAM)

```yaml
Pods no nó:
├─ Pod A: requests 500m CPU, 1GB RAM  ✅ com requests
├─ Pod B: requests 200m CPU, 512MB RAM ✅ com requests
└─ Pod C: SEM requests definidos       ❌ problema

Cálculo do Karpenter:
Utilização = (500m + 200m + 0m) / 2000m = 35% CPU
           = (1GB + 512MB + 0MB) / 4GB = 38% Memory

Karpenter vê: "Nó está 35-38% utilizado - posso consolidar!"
Realidade: Pod C pode estar usando 500m CPU e 1GB RAM!
```

## O que Pode Acontecer

### 1. Consolidação Prematura

```
1. Karpenter vê nó "vazio" (35% utilizado)
2. Decide consolidar
3. Evicts todos os pods (incluindo Pod C sem requests)
4. Pod C é reagendado em outro nó
5. Pod C reinicia (downtime de 10-30 segundos)
```

### 2. Falha de Scheduling

```
1. Karpenter move Pod C para nó com "espaço"
2. Pod C na verdade usa muitos recursos
3. Nó destino fica sobrecarregado
4. Pod C é evicted por pressão de recursos
5. Pod C fica em CrashLoopBackOff
```

## Como Adicionar Resource Requests

### 1. Deployments/StatefulSets

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      containers:
        - name: app
          image: nginx
          resources:
            requests:
              cpu: 100m      # ← ADICIONAR
              memory: 128Mi  # ← ADICIONAR
            limits:
              cpu: 500m
              memory: 512Mi
```

### 2. Helm Charts

```yaml
# values.yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

### 3. Terraform (Helm Release)

```hcl
resource "helm_release" "my_app" {
  # ...
  values = [
    yamlencode({
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }
    })
  ]
}
```

### 4. Crossplane (DeploymentRuntimeConfig)

Para Crossplane providers e functions:

```yaml
apiVersion: pkg.crossplane.io/v1beta1
kind: DeploymentRuntimeConfig
metadata:
  name: my-provider-config
spec:
  deploymentTemplate:
    spec:
      template:
        spec:
          containers:
            - name: package-runtime
              resources:
                requests:
                  cpu: 100m
                  memory: 256Mi
                limits:
                  cpu: 500m
                  memory: 512Mi
```

## Como Dimensionar Requests

### Regras Gerais

1. **Requests**: Recursos **garantidos** (mínimo necessário)
2. **Limits**: Recursos **máximos** (teto)
3. **Requests ≤ Limits** sempre

### Recomendações por Tipo de Workload

#### Workloads Leves (controllers, operators)
```yaml
requests:
  cpu: 50m
  memory: 128Mi
limits:
  cpu: 200m
  memory: 256Mi
```

#### Workloads Médias (APIs, web apps)
```yaml
requests:
  cpu: 100m
  memory: 256Mi
limits:
  cpu: 500m
  memory: 512Mi
```

#### Workloads Pesadas (databases, caches)
```yaml
requests:
  cpu: 500m
  memory: 1Gi
limits:
  cpu: 2000m
  memory: 4Gi
```

### Como Descobrir Valores Corretos

#### 1. Monitorar uso real

```bash
# Ver uso atual dos pods
kubectl top pods -A

# Ver uso dos containers
kubectl top pods -n my-namespace --containers
```

#### 2. Usar métricas históricas

```bash
# Prometheus query (últimos 7 dias)
max_over_time(container_cpu_usage_seconds_total[7d])
max_over_time(container_memory_working_set_bytes[7d])
```

#### 3. Começar conservador e ajustar

```
Requests iniciais: 2x do uso médio observado
Limits iniciais: 4x do uso médio observado

Ajustar após 1 semana de observação
```

## Verificação

### Script Automático

```bash
# Usar script incluído neste repositório
./scripts/check-resource-requests.sh

# Saída esperada:
# ✅ Todos os pods têm resource requests definidos
```

### Verificação Manual

```bash
# Listar pods sem requests
kubectl get pods -A -o json | jq -r '
.items[] | 
select(.spec.containers[].resources.requests == null) | 
"\(.metadata.namespace)/\(.metadata.name)"
'

# Se retornar vazio = SUCCESS!
```

## Impacto da Consolidação

### COM Resource Requests ✅

```
Antes: 10 nós com utilização 30-40%
Depois: 6 nós com utilização 60-70%

Economia: 40% (4 nós a menos)
Custo: $0 (apenas movimentação de pods)
```

### SEM Resource Requests ❌

```
Antes: 10 nós
Depois: 8 nós (consolidação subótima)

Economia: 20% (menos eficiente)
Risco: Pods podem ser evicted incorretamente
```

## Best Practices

1. ✅ **SEMPRE** defina requests para todos os pods
2. ✅ Requests baseados em uso real (monitoring)
3. ✅ Limits 2-4x maiores que requests (burst capacity)
4. ✅ Revise requests trimestralmente
5. ✅ Use PDBs para workloads críticos
6. ❌ **NUNCA** deixe requests vazios
7. ❌ **NUNCA** use requests = limits (desperdiça recursos)

## Ferramentas Úteis

### Kubecost
- Mostra requests vs uso real
- Identifica over/under-provisioning
- Recomenda ajustes

### Vertical Pod Autoscaler (VPA)
- Recomenda requests automaticamente
- Baseado em uso histórico
- Pode atualizar requests automaticamente

### Goldilocks
- Combina VPA com visualização
- Recomendações por namespace
- Dashboard web

## Referências

- [Kubernetes Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Karpenter Consolidation](https://karpenter.sh/docs/concepts/disruption/#consolidation)
- [VPA Documentation](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
