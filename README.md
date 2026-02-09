# Karpenter Best Practices

![Karpenter Version](https://img.shields.io/badge/Karpenter-v1.8.6-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![AWS](https://img.shields.io/badge/AWS-EKS-orange)

> Guia completo de melhores práticas do Karpenter para Amazon EKS - desde instalação básica até otimizações avançadas de custo.

## 🎯 O que é este guia?

Este repositório contém um guia abrangente de melhores práticas para implementar e otimizar o [Karpenter](https://karpenter.sh/) em clusters Amazon EKS. Baseado em experiência real de produção, este guia cobre:

- ✅ Instalação passo a passo (Terraform e Helm)
- ✅ Configurações otimizadas para diferentes ambientes
- ✅ Estratégias de otimização de custos (30-40% economia)
- ✅ Exemplos prontos para uso
- ✅ Troubleshooting de problemas reais
- ✅ Scripts de validação e análise

## 🚀 Quick Start (5 minutos)

### Pré-requisitos

- Cluster EKS (versão 1.28+)
- Terraform 1.5+ ou Helm 3.12+
- kubectl configurado
- AWS CLI com credenciais

### Instalação Básica

```bash
# 1. Clone este repositório
git clone https://github.com/matheusmaais/karpenter-best-practices.git
cd karpenter-best-practices

# 2. Use o exemplo básico
cd examples/basic/terraform

# 3. Configure suas variáveis
cp terraform.tfvars.example terraform.tfvars
# Edite terraform.tfvars com seus valores

# 4. Deploy
terraform init
terraform plan
terraform apply

# 5. Valide a instalação
kubectl get pods -n karpenter
kubectl get nodepools
```

## 📚 Documentação

### Fundamentos

- [01. Introdução](docs/01-introduction.md) - O que é Karpenter e quando usar
- [02. Arquitetura](docs/02-architecture.md) - Como funciona internamente

### Instalação

- [Pré-requisitos](docs/03-installation/prerequisites.md)
- [Instalação via Terraform](docs/03-installation/terraform-installation.md)
- Instalação via Helm - 🚧 Em desenvolvimento
- Validação - 🚧 Em desenvolvimento

### Configuração

- [NodePools e EC2NodeClass](docs/04-configuration/nodepools.md)
- [Spot Instances](docs/04-configuration/spot-instances.md)
- [AWS Graviton (ARM64)](docs/04-configuration/graviton.md)
- Seleção de Instance Types - 🚧 Em desenvolvimento
- Multi-Arquitetura - 🚧 Em desenvolvimento

### Otimização de Custos 💰

- [Consolidação de Nós](docs/05-cost-optimization/consolidation.md) - **Economia de 30-40%**
- [Resource Requests](docs/05-cost-optimization/resource-requests.md) - **CRÍTICO**
- Estratégias Spot - 🚧 Em desenvolvimento
- Monitoramento de Custos - 🚧 Em desenvolvimento

### Produção

- [Segurança e IRSA](docs/06-production-ready/security.md)
- Alta Disponibilidade - 🚧 Em desenvolvimento
- Disruption Budgets - 🚧 Em desenvolvimento
- Observabilidade - 🚧 Em desenvolvimento

### Troubleshooting

- [Problemas Comuns](docs/07-troubleshooting/common-issues.md)
- [FAQ](docs/07-troubleshooting/faq.md)
- Debugging - 🚧 Em desenvolvimento

### Migração

- Migração do Cluster Autoscaler - 🚧 Em desenvolvimento

## 💡 Exemplos Práticos

### [Exemplo Básico](examples/basic/)
Setup mínimo para começar rapidamente.

### [Exemplo Produção](examples/production/)
Configuração completa para ambientes de produção com:
- Bootstrap node group
- Múltiplos NodePools (ARM64 + AMD64)
- Alta disponibilidade
- Monitoramento integrado

### [Otimizado para Custo - Dev](examples/cost-optimized/dev-environment/)
Configuração agressiva para ambientes de desenvolvimento:
- **Economia: 30-40%**
- Consolidação WhenUnderutilized
- 100% Spot instances
- ARM64 Graviton
- Timers rápidos (30s)

### Otimizado para Custo - Prod
🚧 Em desenvolvimento - Configuração balanceada para produção

### Multi-Tenancy
🚧 Em desenvolvimento - Múltiplos NodePools para diferentes workloads

## 🛠️ Scripts Úteis

- [`validate-installation.sh`](scripts/validate-installation.sh) - Valida instalação do Karpenter
- [`check-resource-requests.sh`](scripts/check-resource-requests.sh) - Verifica pods sem requests
- [`cost-analysis.sh`](scripts/cost-analysis.sh) - Análise de custos e economia

## 📊 Casos de Uso

### ✅ Quando usar Karpenter

- Workloads com demanda variável
- Necessidade de otimização de custos
- Múltiplos tipos de workloads (CPU, GPU, memory-intensive)
- Clusters com Spot instances
- Ambientes com ARM64/Graviton

### ❌ Quando NÃO usar Karpenter

- Clusters muito pequenos (< 10 nós)
- Workloads 100% estáveis e previsíveis
- Requisitos de compliance que impedem Spot
- Time sem experiência em Kubernetes

## 🆚 Karpenter vs Cluster Autoscaler

| Característica | Karpenter | Cluster Autoscaler |
|----------------|-----------|-------------------|
| **Velocidade** | ~1 minuto | ~3-5 minutos |
| **Flexibilidade** | Alta (qualquer instance type) | Limitada (node groups) |
| **Consolidação** | Automática e inteligente | Manual via node groups |
| **Spot** | Nativo e otimizado | Suporte básico |
| **Complexidade** | Moderada | Baixa |
| **Custo** | 20-40% menor | Baseline |

## 💰 Economia Esperada

Baseado em experiência real:

- **Dev Environment**: 30-40% de redução (~$150-300/mês para 5-10 nós)
- **Prod Environment**: 20-30% de redução (~$500-1000/mês para 20-30 nós)

Principais fatores:
- Consolidação inteligente de nós
- Spot instances com diversidade
- ARM64 Graviton (20% melhor custo/performance)
- Eliminação de over-provisioning

## 🎓 Diferenciais deste Guia

1. **Experiência Real**: Baseado em implementação de produção
2. **Foco em ROI**: Seção dedicada a otimização de custos
3. **Exemplos Prontos**: Código Terraform/Kubernetes pronto para usar
4. **Troubleshooting Prático**: Problemas reais e soluções testadas
5. **Multi-Arquitetura**: Cobertura completa de ARM64/Graviton
6. **Scripts Úteis**: Ferramentas de validação e análise
7. **Atualizado**: Karpenter v1.8.6 (2024)

## 🤝 Contribuindo

Contribuições são bem-vindas! Por favor:

1. Fork este repositório
2. Crie uma branch para sua feature (`git checkout -b feature/amazing-feature`)
3. Commit suas mudanças (`git commit -m 'Add amazing feature'`)
4. Push para a branch (`git push origin feature/amazing-feature`)
5. Abra um Pull Request

## 📝 Licença

Este projeto está licenciado sob a MIT License - veja o arquivo [LICENSE](LICENSE) para detalhes.

## 🔗 Referências

- [Documentação Oficial do Karpenter](https://karpenter.sh/)
- [AWS EKS Best Practices Guide](https://aws.github.io/aws-eks-best-practices/)
- [Terraform AWS EKS Module](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest)
- [AWS Blog - Karpenter](https://aws.amazon.com/blogs/containers/tag/karpenter/)

## 📧 Contato

Matheus Andrade - [@matheusmaais](https://github.com/matheusmaais)

---

⭐ Se este guia foi útil, considere dar uma estrela no repositório!
