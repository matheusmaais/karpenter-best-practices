# Introdução ao Karpenter

## O que é Karpenter?

Karpenter é um **autoscaler de nós open-source** para Kubernetes, projetado especificamente para Amazon EKS. Diferente do Cluster Autoscaler tradicional, o Karpenter provisiona nós de forma inteligente e rápida baseado nas necessidades reais dos pods.

### Principais Características

- **Provisionamento Rápido**: Nós prontos em ~1 minuto (vs 3-5 min do Cluster Autoscaler)
- **Flexibilidade Total**: Seleciona automaticamente o melhor instance type
- **Consolidação Inteligente**: Remove e reorganiza nós para otimizar custos
- **Spot Nativo**: Suporte otimizado para Spot instances
- **Multi-Arquitetura**: Suporte nativo para ARM64 (Graviton) e AMD64

## Por que usar Karpenter?

### Vantagens

1. **Economia de Custos** (20-40%)
   - Consolidação automática de nós
   - Melhor aproveitamento de Spot instances
   - Suporte a ARM64/Graviton (20% mais barato)

2. **Velocidade**
   - Provisionamento 3x mais rápido
   - Resposta imediata a mudanças de carga

3. **Simplicidade**
   - Não precisa gerenciar múltiplos node groups
   - Configuração declarativa via CRDs
   - Menos overhead operacional

4. **Flexibilidade**
   - Suporta qualquer instance type
   - Mix de arquiteturas (ARM64 + AMD64)
   - Políticas customizáveis por workload

### Desvantagens

1. **Curva de Aprendizado**
   - Conceitos novos (NodePools, EC2NodeClass)
   - Requer entendimento de resource requests

2. **Complexidade Inicial**
   - Setup mais elaborado que Cluster Autoscaler
   - Requer IAM roles e IRSA configurados

3. **Maturidade**
   - Projeto relativamente novo (GA em 2023)
   - Menos battle-tested que Cluster Autoscaler

## Quando usar Karpenter?

### ✅ Use Karpenter quando:

- Cluster com **workloads variáveis** (batch jobs, APIs com picos)
- Necessidade de **otimização de custos**
- Múltiplos tipos de workloads (**CPU, GPU, memory-intensive**)
- Uso de **Spot instances**
- Interesse em **ARM64/Graviton**
- Cluster **médio a grande** (> 20 nós)

### ❌ NÃO use Karpenter quando:

- Cluster **muito pequeno** (< 10 nós) - overhead não compensa
- Workloads **100% estáveis** e previsíveis - Managed Node Groups são mais simples
- **Compliance** que impede Spot instances
- Time **sem experiência** em Kubernetes - comece com Cluster Autoscaler

## Karpenter vs Cluster Autoscaler

| Aspecto | Karpenter | Cluster Autoscaler |
|---------|-----------|-------------------|
| **Velocidade** | ~1 minuto | ~3-5 minutos |
| **Flexibilidade** | Qualquer instance type | Limitado a node groups |
| **Consolidação** | Automática e inteligente | Manual via node groups |
| **Spot** | Nativo e otimizado | Suporte básico |
| **Configuração** | CRDs (NodePools) | Node Groups + ASG |
| **Complexidade** | Moderada | Baixa |
| **Custo** | 20-40% menor | Baseline |
| **Maturidade** | GA desde 2023 | Maduro (2016) |

## Karpenter vs Managed Node Groups

| Aspecto | Karpenter | Managed Node Groups |
|---------|-----------|-------------------|
| **Escalabilidade** | Automática e dinâmica | Manual ou via ASG |
| **Diversidade** | Múltiplos instance types | 1 tipo por node group |
| **Custo** | Otimizado (consolidação) | Fixo ou over-provisioned |
| **Operacional** | Menos overhead | Mais node groups para gerenciar |
| **Uso** | Workloads dinâmicas | Workloads estáticas |

## Conceitos Fundamentais

### NodePool

Define **quando e como** provisionar nós:
- Requirements (arch, instance types, capacity type)
- Limits (CPU, memory máximos)
- Disruption policies (consolidação, expiração)
- Weight (priorização entre NodePools)

### EC2NodeClass

Define **o que** provisionar:
- AMI (Amazon Linux 2023, Bottlerocket, etc)
- Subnets e security groups
- IAM role
- User data e configurações de disco

### Disruption

Políticas de como o Karpenter pode **remover ou substituir** nós:
- **Consolidation**: Reorganizar pods em menos nós
- **Expiration**: Rotacionar nós antigos
- **Drift**: Atualizar nós com configuração desatualizada

## Arquitetura de Alto Nível

```
┌─────────────────────────────────────────┐
│ Kubernetes Scheduler                    │
│ - Detecta pods Pending                  │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│ Karpenter Controller                    │
│ - Analisa requirements dos pods        │
│ - Seleciona melhor instance type       │
│ - Provisiona nó via EC2 API            │
└─────────────────┬───────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────┐
│ AWS EC2                                 │
│ - Cria instância                        │
│ - Registra no EKS                       │
│ - Pods são agendados                    │
└─────────────────────────────────────────┘
```

## Versões e Compatibilidade

### Karpenter v1.8.6 (usado neste guia)

- **Kubernetes**: 1.28, 1.29, 1.30, 1.31
- **EKS**: 1.28+
- **Features**:
  - Consolidation (WhenEmpty, WhenUnderutilized, WhenEmptyOrUnderutilized)
  - Spot-to-Spot consolidation
  - Drift detection
  - Multi-architecture support

### Upgrade Path

- Karpenter segue semantic versioning
- Upgrades dentro da mesma major version são seguros
- Sempre testar em ambiente não-produção primeiro

## Próximos Passos

1. [Entenda a Arquitetura](02-architecture.md) - Como funciona internamente
2. [Pré-requisitos](03-installation/prerequisites.md) - O que você precisa
3. [Instalação](03-installation/terraform-installation.md) - Deploy do Karpenter

## Referências

- [Documentação Oficial](https://karpenter.sh/)
- [AWS Blog - Introducing Karpenter](https://aws.amazon.com/blogs/aws/introducing-karpenter-an-open-source-high-performance-kubernetes-cluster-autoscaler/)
- [EKS Best Practices - Karpenter](https://aws.github.io/aws-eks-best-practices/karpenter/)
