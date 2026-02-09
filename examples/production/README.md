# Exemplo Produção - Karpenter

Setup completo para ambientes de produção com alta disponibilidade, segurança e otimização de custos.

## Características

- ✅ Bootstrap node group on-demand (estabilidade do Karpenter)
- ✅ Múltiplos NodePools (ARM64 + AMD64)
- ✅ Mix Spot + On-Demand (balance custo/disponibilidade)
- ✅ Consolidação moderada (WhenUnderutilized)
- ✅ Alta disponibilidade (multi-AZ)
- ✅ Segurança (IRSA, IMDSv2, encryption)
- ✅ Observabilidade (logs, métricas)

## Arquitetura

```
┌─────────────────────────────────────────────────┐
│ Bootstrap Node Group (On-Demand, Multi-AZ)     │
│ - Karpenter controller                          │
│ - CoreDNS, VPC-CNI                             │
│ - Monitoring (Prometheus, etc)                  │
│ - Taint: CriticalAddonsOnly                    │
│ - Min: 2, Max: 3, Desired: 2                   │
└─────────────────────────────────────────────────┘
                      │
                      │ Provisiona
                      ▼
┌─────────────────────────────────────────────────┐
│ NodePool 1: ARM64 Spot (Priority 10)           │
│ - 80% dos workloads                             │
│ - Consolidation: WhenUnderutilized (5min)      │
│ - Expire: 30 days                               │
└─────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────┐
│ NodePool 2: AMD64 Spot (Priority 20)           │
│ - Fallback para workloads incompatíveis         │
│ - Consolidation: WhenUnderutilized (5min)      │
└─────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────┐
│ NodePool 3: On-Demand (Priority 100)           │
│ - Workloads críticos                            │
│ - Consolidation: WhenEmpty (10min)             │
└─────────────────────────────────────────────────┘
```

## Estrutura

```
production/
├── terraform/
│   ├── main.tf                    # Providers
│   ├── eks.tf                     # EKS cluster + bootstrap
│   ├── karpenter.tf               # Karpenter IAM + Helm
│   ├── nodepools.tf               # 3 NodePools
│   ├── monitoring.tf              # Prometheus, Grafana
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
└── manifests/
    ├── nodepools/
    │   ├── arm64-spot.yaml
    │   ├── amd64-spot.yaml
    │   └── on-demand.yaml
    ├── ec2nodeclasses/
    │   ├── arm64.yaml
    │   ├── amd64.yaml
    │   └── on-demand.yaml
    └── pdbs/
        └── karpenter-pdb.yaml
```

## Configuração

### Bootstrap Node Group

```hcl
# eks.tf
resource "aws_eks_node_group" "bootstrap" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "bootstrap"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids

  instance_types = ["t4g.medium"]  # ARM64
  capacity_type  = "ON_DEMAND"     # Não usar Spot para bootstrap

  scaling_config {
    min_size     = 2  # HA
    max_size     = 3
    desired_size = 2
  }

  # Taint para evitar workloads normais
  taint {
    key    = "CriticalAddonsOnly"
    value  = "true"
    effect = "NO_SCHEDULE"
  }

  labels = {
    role = "bootstrap"
  }
}
```

### NodePool ARM64 Spot (Primary)

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: arm64-spot
spec:
  template:
    spec:
      nodeClassRef:
        name: arm64
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["t", "c", "m", "r"]  # Diversidade
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["3"]
  
  limits:
    cpu: "500"
    memory: 1000Gi
  
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 5m      # Conservador para prod
    expireAfter: 720h         # 30 days
    budgets:
      - nodes: "5%"           # Máximo 5% por vez
  
  weight: 10  # Highest priority
```

### NodePool On-Demand (Critical)

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: on-demand-critical
spec:
  template:
    metadata:
      labels:
        capacity-type: on-demand
    spec:
      nodeClassRef:
        name: on-demand
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
      taints:
        - key: workload-priority
          value: critical
          effect: NoSchedule
  
  limits:
    cpu: "100"
    memory: 200Gi
  
  disruption:
    consolidationPolicy: WhenEmpty  # Conservador
    consolidateAfter: 10m
    expireAfter: Never              # Não expirar
    budgets:
      - nodes: "1"                  # Um nó por vez
  
  weight: 100  # Lowest priority (mais caro)
```

## Alta Disponibilidade

### Karpenter Controller HA

```yaml
# Helm values
replicas: 2  # Múltiplas réplicas

affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: karpenter
        topologyKey: kubernetes.io/hostname
```

### PodDisruptionBudget

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: karpenter
  namespace: karpenter
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: karpenter
```

### Topology Spread

```yaml
# Para workloads críticos
spec:
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
      labelSelector:
        matchLabels:
          app: my-critical-app
```

## Monitoramento

### Prometheus Metrics

```yaml
# ServiceMonitor para Prometheus Operator
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: karpenter
  namespace: karpenter
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: karpenter
  endpoints:
    - port: http-metrics
      interval: 30s
```

### Métricas Importantes

- `karpenter_nodes_created` - Nós criados
- `karpenter_nodes_terminated` - Nós terminados
- `karpenter_pods_startup_time` - Tempo de startup
- `karpenter_nodeclaims_disrupted` - Disruptions
- `karpenter_interruption_actions_performed` - Interrupções Spot

### Alertas

```yaml
# PrometheusRule
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: karpenter-alerts
spec:
  groups:
    - name: karpenter
      rules:
        - alert: KarpenterHighInterruptionRate
          expr: rate(karpenter_interruption_actions_performed[5m]) > 0.1
          annotations:
            summary: "Alta taxa de interrupções Spot"
        
        - alert: KarpenterNodeProvisioningFailed
          expr: karpenter_nodeclaims_created - karpenter_nodes_created > 5
          annotations:
            summary: "Falha ao provisionar nós"
```

## Deployment

### Passo 1: Deploy Infrastructure

```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

### Passo 2: Validar Bootstrap

```bash
# Verificar bootstrap nodes
kubectl get nodes -l role=bootstrap

# Deve ter 2 nós on-demand
```

### Passo 3: Deploy Karpenter

```bash
# Já deployado via Terraform
kubectl get pods -n karpenter
kubectl get nodepools
```

### Passo 4: Testar Scaling

```bash
# Deployment de teste
kubectl create deployment test --image=nginx --replicas=50

# Ver nós sendo provisionados
kubectl get nodes -w

# Limpar
kubectl delete deployment test
```

## Economia vs Disponibilidade

### Configuração Atual

```
Bootstrap (On-Demand): 2x t4g.medium = $49/mês
ARM64 Spot (80%): 40x m6g.large Spot = $674/mês
AMD64 Spot (15%): 7x m5.large Spot = $149/mês
On-Demand (5%): 3x m6g.large On-Demand = $169/mês

Total: $1,041/mês
```

### Comparação com Full On-Demand

```
Full On-Demand: 50x m6g.large = $2,821/mês

Economia: $1,780/mês (63%)
```

### Comparação com Full Spot (sem fallback)

```
Full Spot: 50x m6g.large Spot = $842/mês

Diferença: $199/mês (24% mais caro)
Benefício: Alta disponibilidade garantida
```

## Rollout Strategy

### Fase 1: Deploy com On-Demand

```yaml
# Iniciar conservador
requirements:
  - key: karpenter.sh/capacity-type
    operator: In
    values: ["on-demand"]
```

### Fase 2: Adicionar Spot com baixa prioridade

```yaml
# NodePool Spot com weight alto (baixa prioridade)
weight: 100
```

### Fase 3: Inverter prioridades

```yaml
# Spot preferred
weight: 10
```

### Fase 4: Habilitar consolidação

```yaml
disruption:
  consolidationPolicy: WhenUnderutilized
```

## Troubleshooting Produção

### Alta taxa de interrupções Spot

**Solução**: Aumentar diversidade ou aumentar % On-Demand

### Consolidação muito agressiva

**Solução**: Aumentar `consolidateAfter` e reduzir budget

### Custos acima do esperado

**Solução**: Verificar se consolidação está funcionando

## Referências

- [High Availability Guide](high-availability.md)
- [Security Guide](security.md)
- [Observability Guide](observability.md)
- [Disruption Budgets](disruption-budgets.md)
