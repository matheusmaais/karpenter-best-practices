#!/bin/bash
#
# Script para verificar pods sem resource requests em nós Karpenter
# Uso: ./check-resource-requests.sh
#

set -e

echo "🔍 Verificando pods sem resource requests em nós Karpenter..."
echo ""

# Verificar se kubectl está configurado
if ! kubectl cluster-info &>/dev/null; then
  echo "❌ kubectl não está configurado ou cluster não está acessível"
  exit 1
fi

# Listar pods sem requests em nós Karpenter
echo "📋 Pods SEM resource requests em nós gerenciados pelo Karpenter:"
echo ""

pods_without_requests=$(kubectl get pods -A -o json | jq -r '
.items[] | 
select(
  .spec.nodeName != null and
  (.metadata.labels["node.kubernetes.io/managed-by"] // "" | contains("karpenter") or
   .spec.nodeName | test("^ip-"))
) |
select(
  .spec.containers[] | 
  select(.resources.requests == null or .resources.requests == {})
) | 
"\(.metadata.namespace)/\(.metadata.name) - container: \(.spec.containers[0].name) - node: \(.spec.nodeName)"
' | sort -u)

if [ -z "$pods_without_requests" ]; then
  echo "✅ Perfeito! Todos os pods em nós Karpenter têm resource requests definidos."
  echo ""
  exit 0
fi

echo "$pods_without_requests"
echo ""

# Contar pods problemáticos
count=$(echo "$pods_without_requests" | wc -l | tr -d ' ')
echo "⚠️  Total: $count pods sem resource requests"
echo ""

# Listar deployments/statefulsets afetados
echo "📦 Deployments/StatefulSets afetados:"
echo ""

kubectl get deploy,sts -A -o json | jq -r '
.items[] | 
select(
  .spec.template.spec.containers[] | 
  select(.resources.requests == null or .resources.requests == {})
) | 
"\(.kind)/\(.metadata.namespace)/\(.metadata.name)"
' | sort -u

echo ""
echo "⚠️  ATENÇÃO:"
echo "   Pods sem resource requests podem causar problemas com consolidação do Karpenter!"
echo ""
echo "💡 Soluções:"
echo "   1. Adicione resource requests nos deployments/statefulsets"
echo "   2. Configure via Helm values (se instalado via Helm)"
echo "   3. Use DeploymentRuntimeConfig (para Crossplane providers/functions)"
echo ""
echo "📚 Mais informações:"
echo "   https://github.com/matheusmaais/karpenter-best-practices/blob/main/docs/05-cost-optimization/resource-requests.md"
echo ""

exit 1
