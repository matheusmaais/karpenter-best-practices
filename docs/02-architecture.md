# Arquitetura do Karpenter

## Visão Geral

O Karpenter opera como um controller dentro do cluster Kubernetes, monitorando pods pending e provisionando nós de forma inteligente e rápida.

## Componentes Principais

```mermaid
graph TB
    subgraph k8s [Kubernetes Cluster]
        scheduler[Kubernetes Scheduler]
        karpenter[Karpenter Controller]
        pods[Pods Pending]
        nodes[Worker Nodes]
    end
    
    subgraph aws [AWS]
        ec2[EC2 API]
        sqs[SQS Queue]
        iam[IAM IRSA]
    end
    
    scheduler -->|detecta pods pending| karpenter
    karpenter -->|provisiona via| ec2
    ec2 -->|cria| nodes
    nodes -->|agenda| pods
    sqs -->|spot interruptions| karpenter
    iam -->|autentica| karpenter
