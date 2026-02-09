# Problemas Comuns e Soluções

## 1. Nós Não São Provisionados

### Sintoma

Pods ficam em estado `Pending` indefinidamente.

```bash
kubectl get pods -A | grep Pending
```

### Causas e Soluções

#### A. IAM Role não configurado

**Verificar:**
```bash
kubectl describe sa -n karpenter karpenter
# Deve ter annotation: eks.amazonaws.com/role-arn
```

**Solução:**
```bash
# Verificar role ARN
aws iam get-role --role-name KarpenterController-my-cluster

# Re-aplicar Terraform se necessário
terraform apply -target=module.karpenter
```

#### B. Subnets sem tag

**Verificar:**
```bash
aws ec2 describe-subnets \
  --filters "Name=tag:karpenter.sh/discovery,Values=my-cluster" \
  --query 'Subnets[].SubnetId'
```

**Solução:**
```bash
aws ec2 create-tags \
  --resources subnet-xxxxx subnet-yyyyy \
  --tags Key=karpenter.sh/discovery,Value=my-cluster
```

#### C. Capacity não disponível

**Verificar logs:**
```bash
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | grep -i "insufficient capacity"
```

**Solução:**
- Aumentar diversidade de instance types
- Adicionar mais AZs
- Considerar On-Demand como fallback

#### D. Limits excedidos

**Verificar:**
```bash
kubectl describe nodepool default
# Ver spec.limits
```

**Solução:**
```yaml
# Aumentar limits
limits:
  cpu: "200"      # Era: 100
  memory: 400Gi   # Era: 200Gi
```

## 2. Pods Não Agendam em Nós Karpenter

### Sintoma

Nós são criados mas pods continuam Pending.

### Causas e Soluções

#### A. Taints não tolerados

**Verificar:**
```bash
kubectl describe node <node-name> | grep Taints
kubectl describe pod <pod-name> | grep Tolerations
```

**Solução:**
```yaml
# Adicionar toleration no pod
tolerations:
  - key: "my-taint"
    operator: "Exists"
    effect: "NoSchedule"
```

#### B. Node affinity incompatível

**Verificar:**
```bash
kubectl describe pod <pod-name> | grep -A 10 "Node-Selectors\|Affinity"
```

**Solução:**
- Ajustar node affinity do pod
- Ou ajustar labels do NodePool

#### C. Resource requests muito altos

**Verificar:**
```bash
kubectl describe pod <pod-name> | grep -A 5 "Requests"
kubectl describe node <node-name> | grep "Allocatable"
```

**Solução:**
- Reduzir requests do pod
- Ou permitir instance types maiores no NodePool

## 3. Consolidação Não Funciona

### Sintoma

Nós permanecem ativos mesmo com baixa utilização.

### Causas e Soluções

#### A. Pods sem resource requests

**Verificar:**
```bash
./scripts/check-resource-requests.sh
```

**Solução:**
Ver guia: [Resource Requests](../05-cost-optimization/resource-requests.md)

#### B. PodDisruptionBudgets bloqueando

**Verificar:**
```bash
kubectl get pdb -A
kubectl describe pdb <pdb-name>
```

**Solução:**
- Ajustar PDB (minAvailable ou maxUnavailable)
- Ou aumentar número de replicas

#### C. Consolidação desabilitada

**Verificar:**
```bash
kubectl get nodepool default -o yaml | grep consolidation
```

**Solução:**
```yaml
# Habilitar consolidação
disruption:
  consolidationPolicy: WhenUnderutilized  # Não pode ser vazio
```

## 4. Muitas Interrupções Spot

### Sintoma

Pods reiniciam frequentemente devido a Spot interruptions.

### Causas e Soluções

#### A. Pouca diversidade de instance types

**Verificar:**
```bash
kubectl get nodepool default -o yaml | grep -A 20 requirements
```

**Solução:**
```yaml
# Permitir mais instance types
requirements:
  - key: karpenter.k8s.aws/instance-category
    operator: In
    values: ["t", "c", "m"]  # Mais opções
```

#### B. Interruption handling não configurado

**Verificar:**
```bash
kubectl get deployment -n karpenter karpenter -o yaml | grep interruptionQueue
```

**Solução:**
```yaml
# Configurar no Helm
settings:
  interruptionQueue: my-cluster-karpenter-queue
```

#### C. Região com pouca capacidade Spot

**Solução:**
- Adicionar On-Demand como fallback
- Considerar outras regiões/AZs

## 5. Custos Mais Altos que Esperado

### Causas e Soluções

#### A. Consolidação não habilitada

**Solução:**
```yaml
disruption:
  consolidationPolicy: WhenUnderutilized
```

#### B. Usando On-Demand ao invés de Spot

**Verificar:**
```bash
kubectl get nodes -L karpenter.sh/capacity-type
```

**Solução:**
```yaml
requirements:
  - key: karpenter.sh/capacity-type
    operator: In
    values: ["spot"]  # Forçar Spot
```

#### C. Instance types caros sendo usados

**Verificar:**
```bash
kubectl get nodes -L node.kubernetes.io/instance-type
```

**Solução:**
```yaml
# Restringir a instance types mais baratos
requirements:
  - key: karpenter.k8s.aws/instance-category
    operator: In
    values: ["t"]  # Apenas T-family
```

## 6. Karpenter Controller Crashando

### Sintoma

```bash
kubectl get pods -n karpenter
# CrashLoopBackOff ou Error
```

### Causas e Soluções

#### A. Recursos insuficientes

**Verificar:**
```bash
kubectl describe pod -n karpenter <pod-name> | grep -A 5 "Limits\|Requests"
kubectl top pod -n karpenter
```

**Solução:**
```yaml
# Aumentar resources
resources:
  limits:
    cpu: 2000m    # Era: 1000m
    memory: 2Gi   # Era: 1Gi
```

#### B. IRSA não funcionando

**Verificar:**
```bash
kubectl logs -n karpenter <pod-name> | grep -i "credential\|auth\|sts"
```

**Solução:**
- Verificar OIDC provider configurado
- Verificar trust relationship do IAM role
- Verificar annotation no ServiceAccount

#### C. Versão incompatível

**Verificar:**
```bash
kubectl version
helm list -n karpenter
```

**Solução:**
- Verificar compatibility matrix
- Upgrade do Karpenter se necessário

## 7. Nós Não São Removidos

### Sintoma

Nós vazios permanecem ativos.

### Causas e Soluções

#### A. Pods do sistema bloqueando

**Verificar:**
```bash
kubectl get pods -o wide | grep <node-name>
```

**Solução:**
- DaemonSets são ignorados (normal)
- Verificar se há pods "stuck"

#### B. Consolidação muito conservadora

**Verificar:**
```bash
kubectl get nodepool default -o yaml | grep consolidateAfter
```

**Solução:**
```yaml
# Reduzir tempo de espera
consolidateAfter: 30s  # Era: 5m
```

## Comandos Úteis de Debug

### Logs do Karpenter

```bash
# Logs em tempo real
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter -f

# Últimas 100 linhas
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100

# Filtrar por erro
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | grep -i error
```

### Status dos Recursos

```bash
# NodePools
kubectl get nodepools
kubectl describe nodepool <name>

# EC2NodeClasses
kubectl get ec2nodeclasses
kubectl describe ec2nodeclass <name>

# NodeClaims (nós sendo provisionados)
kubectl get nodeclaims
```

### Eventos

```bash
# Eventos do Karpenter
kubectl get events -n karpenter --sort-by='.lastTimestamp'

# Eventos de pods
kubectl get events -A | grep <pod-name>
```

### Métricas

```bash
# Utilização de nós
kubectl top nodes

# Utilização de pods
kubectl top pods -A

# Nós por tipo
kubectl get nodes -L node.kubernetes.io/instance-type
```

## Referências

- [Karpenter Troubleshooting](https://karpenter.sh/docs/troubleshooting/)
- [EKS Troubleshooting](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
- [Debugging Guide](debugging.md)
- [FAQ](faq.md)
