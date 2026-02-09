# AWS Graviton (ARM64) com Karpenter

## O que é AWS Graviton?

Graviton são processadores ARM64 desenvolvidos pela AWS, oferecendo:

- **20% melhor custo/performance** vs x86_64
- **40% melhor eficiência energética**
- **Até 60% melhor performance/watt**

## Benefícios

### 1. Custo

```
Comparação de preços (us-east-1, On-Demand):

x86_64:
- t3.medium:  $0.0416/h = $30.50/mês
- m5.large:   $0.096/h  = $70.40/mês

ARM64 (Graviton):
- t4g.medium: $0.0336/h = $24.60/mês  (19% cheaper)
- m6g.large:  $0.077/h  = $56.50/mês  (20% cheaper)

Economia: ~20% em custos de compute
```

### 2. Performance

- Melhor performance para workloads compute-intensive
- Menor latência em algumas operações
- Melhor throughput de rede

### 3. Sustentabilidade

- 40% menos energia consumida
- Menor pegada de carbono

## Compatibilidade

### ✅ Workloads Compatíveis

- **Linguagens**: Python, Node.js, Go, Rust, Java, Ruby, PHP
- **Containers**: Qualquer imagem multi-arch
- **Databases**: PostgreSQL, MySQL, Redis, MongoDB
- **Web servers**: Nginx, Apache, Caddy
- **Runtimes**: Docker, containerd

### ⚠️ Requer Atenção

- **Binários compilados**: Devem ser ARM64
- **Imagens Docker**: Devem suportar ARM64
- **Dependencies nativas**: Verificar compatibilidade

### ❌ Não Compatíveis

- Software proprietário sem build ARM64
- Aplicações legacy sem suporte ARM
- Algumas ferramentas específicas de x86

## Verificar Compatibilidade

### Imagens Docker

```bash
# Verificar se imagem suporta ARM64
docker manifest inspect nginx:latest | jq '.manifests[] | select(.platform.architecture=="arm64")'

# Ou
docker buildx imagetools inspect nginx:latest | grep arm64
```

### Testar Localmente

```bash
# Em Mac M1/M2/M3 (ARM64)
docker run --platform linux/arm64 nginx:latest

# Em Mac Intel ou Linux x86
docker run --platform linux/arm64 --rm nginx:latest
# Se funcionar, é compatível!
```

## Configuração do Karpenter

### NodePool ARM64

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: arm64
spec:
  template:
    spec:
      nodeClassRef:
        name: arm64
      requirements:
        # ARM64 only
        - key: kubernetes.io/arch
          operator: In
          values: ["arm64"]
        
        # Spot for cost optimization
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        
        # Graviton instance families
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["t", "c", "m", "r"]  # t4g, c6g, m6g, r6g
        
        # Generation >= 4 (Graviton2 and newer)
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["3"]
  
  limits:
    cpu: "100"
    memory: 200Gi
  
  weight: 10  # Higher priority (cheaper)
```

### EC2NodeClass ARM64

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: arm64
spec:
  # AL2023 ARM64 (recommended)
  amiFamily: AL2023
  amiSelectorTerms:
    - alias: al2023@latest
  
  # Or Bottlerocket ARM64
  # amiFamily: Bottlerocket
  # amiSelectorTerms:
  #   - alias: bottlerocket@latest
  
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: my-cluster
  
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: my-cluster
  
  role: KarpenterNodeRole
  
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 50Gi
        volumeType: gp3
        encrypted: true
```

## Migração para Graviton

### Estratégia Gradual (Recomendada)

#### Fase 1: Criar NodePool ARM64 com baixa prioridade

```yaml
# NodePool ARM64 (weight alto = baixa prioridade)
weight: 100

# NodePool AMD64 (weight baixo = alta prioridade)
weight: 10
```

Resultado: Workloads novos vão para AMD64 (existente)

#### Fase 2: Testar workloads em ARM64

```yaml
# Deployment de teste
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-arm64
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/arch: arm64
```

#### Fase 3: Inverter prioridades

```yaml
# NodePool ARM64 (preferred)
weight: 10

# NodePool AMD64 (fallback)
weight: 100
```

Resultado: Workloads novos vão para ARM64

#### Fase 4: Forçar migração

```bash
# Drain nós AMD64 gradualmente
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# Pods serão reagendados em ARM64
```

### Estratégia Agressiva

```yaml
# ARM64 only - sem fallback
requirements:
  - key: kubernetes.io/arch
    operator: In
    values: ["arm64"]
```

**Quando usar:**
- Ambiente de desenvolvimento
- Workloads 100% compatíveis
- Máxima economia

## Famílias Graviton

### Graviton2 (Generation 4)

- **T4g**: Burstable, cost-effective
- **C6g**: Compute-optimized
- **M6g**: General purpose
- **R6g**: Memory-optimized

### Graviton3 (Generation 5-6)

- **C7g**: Compute-optimized (25% faster than C6g)
- **M7g**: General purpose
- **R7g**: Memory-optimized

### Graviton3E (Generation 6)

- **C7gn**: Network-optimized (200 Gbps)
- **R7gd**: Memory + NVMe storage

## Multi-Arch Images

### Build Multi-Arch

```dockerfile
# Dockerfile (compatível com ARM64 e AMD64)
FROM --platform=$BUILDPLATFORM golang:1.21 AS builder
ARG TARGETOS
ARG TARGETARCH

WORKDIR /app
COPY . .
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH go build -o app

FROM alpine:latest
COPY --from=builder /app/app /app
CMD ["/app"]
```

### Build e Push

```bash
# Build para múltiplas arquiteturas
docker buildx build --platform linux/amd64,linux/arm64 \
  -t myrepo/myapp:latest \
  --push .
```

### Verificar

```bash
docker manifest inspect myrepo/myapp:latest
```

## Deployment com Node Affinity

### Preferir ARM64, aceitar AMD64

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: kubernetes.io/arch
                    operator: In
                    values: ["arm64"]
```

### Apenas ARM64

```yaml
nodeSelector:
  kubernetes.io/arch: arm64
```

## Economia Real

### Cluster Dev (10 nós)

```
AMD64 (t3.medium Spot):
10 * $0.0125/h = $0.125/h = $91/mês

ARM64 (t4g.medium Spot):
10 * $0.0101/h = $0.101/h = $74/mês

Economia: $17/mês (19%)
```

### Cluster Prod (50 nós)

```
AMD64 (m5.large Spot):
50 * $0.029/h = $1.45/h = $1,062/mês

ARM64 (m6g.large Spot):
50 * $0.023/h = $1.15/h = $842/mês

Economia: $220/mês (21%)
```

### Combinado com Consolidação

```
Spot + ARM64 + Consolidation:
- Spot: 70% economia vs On-Demand
- ARM64: 20% economia adicional vs x86
- Consolidation: 30-40% economia adicional

Total: 75-85% economia vs On-Demand AMD64 sem consolidação!
```

## Troubleshooting

### Imagem não funciona em ARM64

**Erro:**
```
exec format error
```

**Solução:**
1. Verificar se imagem suporta ARM64
2. Build multi-arch image
3. Ou usar nodeSelector para AMD64

### Performance pior que esperado

**Causa**: Workload não otimizado para ARM

**Solução**:
- Recompilar com otimizações ARM
- Usar flags de compilação específicas
- Testar diferentes versões

### Dependency nativa falha

**Erro:**
```
cannot execute binary file: Exec format error
```

**Solução**:
- Instalar versão ARM64 da dependency
- Ou usar imagem base diferente
- Ou compilar dependency do source

## Referências

- [AWS Graviton](https://aws.amazon.com/ec2/graviton/)
- [Graviton Technical Guide](https://github.com/aws/aws-graviton-getting-started)
- [Multi-Arch Images](https://docs.docker.com/build/building/multi-platform/)
- [Graviton Performance](https://aws.amazon.com/ec2/graviton/performance/)
