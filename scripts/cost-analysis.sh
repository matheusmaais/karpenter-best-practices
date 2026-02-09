#!/bin/bash
#
# Script para análise de custos do Karpenter
# Calcula economia potencial e custos atuais
#

set -e

echo "💰 Análise de Custos - Karpenter"
echo "================================"
echo ""

# Verificar kubectl
if ! kubectl cluster-info &>/dev/null; then
  echo "❌ kubectl não está configurado"
  exit 1
fi

# Contar nós por tipo
echo "📊 Distribuição de Nós:"
echo ""

total_nodes=$(kubectl get nodes --no-headers | wc -l | tr -d ' ')
karpenter_nodes=$(kubectl get nodes -l node.kubernetes.io/managed-by=karpenter --no-headers 2>/dev/null | wc -l | tr -d ' ')
managed_nodes=$((total_nodes - karpenter_nodes))

echo "  Total de nós: $total_nodes"
echo "  Gerenciados pelo Karpenter: $karpenter_nodes"
echo "  Managed Node Groups: $managed_nodes"
echo ""

# Nós por arquitetura
echo "🏗️  Arquitetura:"
echo ""
arm64_count=$(kubectl get nodes -L kubernetes.io/arch --no-headers 2>/dev/null | grep arm64 | wc -l | tr -d ' ')
amd64_count=$(kubectl get nodes -L kubernetes.io/arch --no-headers 2>/dev/null | grep amd64 | wc -l | tr -d ' ')

echo "  ARM64 (Graviton): $arm64_count nós"
echo "  AMD64 (x86_64): $amd64_count nós"
echo ""

# Nós por capacity type
echo "💸 Capacity Type:"
echo ""
spot_count=$(kubectl get nodes -L karpenter.sh/capacity-type --no-headers 2>/dev/null | grep spot | wc -l | tr -d ' ')
ondemand_count=$(kubectl get nodes -L karpenter.sh/capacity-type --no-headers 2>/dev/null | grep -v spot | grep -v "<none>" | wc -l | tr -d ' ')
unknown_count=$((karpenter_nodes - spot_count - ondemand_count))

echo "  Spot: $spot_count nós (~70% economia vs On-Demand)"
echo "  On-Demand: $ondemand_count nós"
if [ "$unknown_count" -gt 0 ]; then
  echo "  Unknown: $unknown_count nós (provavelmente managed node groups)"
fi
echo ""

# Instance types
echo "🖥️  Instance Types (Top 5):"
echo ""
kubectl get nodes -L node.kubernetes.io/instance-type --no-headers 2>/dev/null | \
  awk '{print $6}' | grep -v "<none>" | sort | uniq -c | sort -rn | head -5 | \
  awk '{printf "  %2d nós: %s\n", $1, $2}'
echo ""

# Calcular economia estimada
echo "💰 Economia Estimada:"
echo ""

# Assumindo preços médios (us-east-1)
# t4g.medium On-Demand: $0.0336/h = $24.60/mês
# t4g.medium Spot: $0.0101/h = $7.40/mês
# m6g.large On-Demand: $0.077/h = $56.50/mês
# m6g.large Spot: $0.023/h = $16.90/mês

if [ "$spot_count" -gt 0 ]; then
  spot_savings=$((spot_count * 17))  # ~$17/mês economia por nó Spot
  echo "  Spot instances: ~\$$spot_savings/mês economia (vs On-Demand)"
fi

if [ "$arm64_count" -gt 0 ]; then
  arm64_savings=$((arm64_count * 5))  # ~$5/mês economia por nó ARM64
  echo "  ARM64 (Graviton): ~\$$arm64_savings/mês economia (vs AMD64)"
fi

total_savings=$((spot_savings + arm64_savings))
echo ""
echo "  💵 Total estimado: ~\$$total_savings/mês economia"
echo "     (vs cluster full On-Demand AMD64)"
echo ""

# Consolidação
echo "🔄 Consolidação:"
echo ""

# Verificar NodePools
nodepools=$(kubectl get nodepools --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$nodepools" -gt 0 ]; then
  echo "  NodePools configurados: $nodepools"
  echo ""
  kubectl get nodepools -o custom-columns=\
NAME:.metadata.name,\
POLICY:.spec.disruption.consolidationPolicy,\
AFTER:.spec.disruption.consolidateAfter,\
EXPIRE:.spec.disruption.expireAfter 2>/dev/null || true
  echo ""
  
  # Verificar se há consolidação ativa
  consolidation_logs=$(kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=100 2>/dev/null | grep -i consolidat | wc -l | tr -d ' ')
  if [ "$consolidation_logs" -gt 0 ]; then
    echo "  ✅ Consolidação ativa ($consolidation_logs eventos recentes)"
    echo "     Economia adicional estimada: 30-40%"
  else
    echo "  ⚠️  Nenhuma consolidação detectada nos últimos logs"
    echo "     Verifique se consolidationPolicy está configurada"
  fi
else
  echo "  ⚠️  Nenhum NodePool encontrado"
fi

echo ""

# Utilização
echo "📈 Utilização de Recursos:"
echo ""

if command -v kubectl-top &>/dev/null || kubectl top nodes &>/dev/null 2>&1; then
  echo "  CPU e Memory por nó:"
  kubectl top nodes 2>/dev/null | head -6 || echo "  ⚠️  Metrics server não disponível"
else
  echo "  ⚠️  kubectl top não disponível (instale metrics-server)"
fi

echo ""

# Recomendações
echo "💡 Recomendações:"
echo ""

if [ "$spot_count" -eq 0 ] && [ "$karpenter_nodes" -gt 0 ]; then
  echo "  ⚠️  Nenhum nó Spot detectado - considere usar Spot para economia de 70%"
fi

if [ "$arm64_count" -eq 0 ] && [ "$karpenter_nodes" -gt 0 ]; then
  echo "  ⚠️  Nenhum nó ARM64 detectado - considere Graviton para economia de 20%"
fi

if [ "$consolidation_logs" -eq 0 ] && [ "$nodepools" -gt 0 ]; then
  echo "  ⚠️  Consolidação não detectada - habilite WhenUnderutilized para economia de 30-40%"
fi

if [ "$spot_count" -gt 0 ] && [ "$arm64_count" -gt 0 ] && [ "$consolidation_logs" -gt 0 ]; then
  echo "  ✅ Configuração otimizada! Spot + ARM64 + Consolidação ativa"
  echo "  💰 Economia estimada: 75-85% vs baseline On-Demand AMD64"
fi

echo ""
echo "📚 Mais informações:"
echo "   https://github.com/matheusmaais/karpenter-best-practices"
echo ""
