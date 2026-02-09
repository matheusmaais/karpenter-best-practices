#!/bin/bash
#
# Script para validar instalação do Karpenter
# Uso: ./validate-installation.sh [cluster-name]
#

set -e

CLUSTER_NAME=${1:-""}

if [ -z "$CLUSTER_NAME" ]; then
  echo "Uso: ./validate-installation.sh <cluster-name>"
  exit 1
fi

echo "🔍 Validando instalação do Karpenter no cluster: $CLUSTER_NAME"
echo ""

# Verificar kubectl
if ! kubectl cluster-info &>/dev/null; then
  echo "❌ kubectl não está configurado"
  exit 1
fi
echo "✅ kubectl configurado"

# Verificar namespace karpenter
if ! kubectl get namespace karpenter &>/dev/null; then
  echo "❌ Namespace 'karpenter' não existe"
  exit 1
fi
echo "✅ Namespace 'karpenter' existe"

# Verificar CRDs
echo ""
echo "📦 Verificando CRDs..."
crds=("nodepools.karpenter.sh" "ec2nodeclasses.karpenter.k8s.aws" "nodeclaims.karpenter.sh")
for crd in "${crds[@]}"; do
  if kubectl get crd "$crd" &>/dev/null; then
    echo "  ✅ $crd"
  else
    echo "  ❌ $crd não encontrado"
    exit 1
  fi
done

# Verificar pod do Karpenter
echo ""
echo "🚀 Verificando pod do Karpenter..."
if kubectl get pods -n karpenter -l app.kubernetes.io/name=karpenter | grep -q Running; then
  echo "  ✅ Pod do Karpenter está Running"
  kubectl get pods -n karpenter -l app.kubernetes.io/name=karpenter
else
  echo "  ❌ Pod do Karpenter não está Running"
  kubectl get pods -n karpenter
  exit 1
fi

# Verificar IRSA
echo ""
echo "🔐 Verificando IRSA..."
sa_role=$(kubectl get sa -n karpenter karpenter -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || echo "")
if [ -n "$sa_role" ]; then
  echo "  ✅ ServiceAccount tem role ARN: $sa_role"
else
  echo "  ❌ ServiceAccount não tem role ARN configurado"
  exit 1
fi

# Verificar NodePools
echo ""
echo "📋 Verificando NodePools..."
nodepool_count=$(kubectl get nodepools --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$nodepool_count" -gt 0 ]; then
  echo "  ✅ $nodepool_count NodePool(s) encontrado(s)"
  kubectl get nodepools
else
  echo "  ⚠️  Nenhum NodePool encontrado (isso é normal se ainda não criou)"
fi

# Verificar EC2NodeClasses
echo ""
echo "🖥️  Verificando EC2NodeClasses..."
nodeclass_count=$(kubectl get ec2nodeclasses --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "$nodeclass_count" -gt 0 ]; then
  echo "  ✅ $nodeclass_count EC2NodeClass(es) encontrado(s)"
  kubectl get ec2nodeclasses
else
  echo "  ⚠️  Nenhum EC2NodeClass encontrado (isso é normal se ainda não criou)"
fi

# Verificar tags nas subnets
echo ""
echo "🏷️  Verificando tags nas subnets..."
echo "  (Requer AWS CLI configurado)"
if command -v aws &>/dev/null; then
  subnet_count=$(aws ec2 describe-subnets \
    --filters "Name=tag:karpenter.sh/discovery,Values=$CLUSTER_NAME" \
    --query 'Subnets[].SubnetId' \
    --output text 2>/dev/null | wc -w | tr -d ' ')
  
  if [ "$subnet_count" -gt 0 ]; then
    echo "  ✅ $subnet_count subnet(s) com tag karpenter.sh/discovery=$CLUSTER_NAME"
  else
    echo "  ❌ Nenhuma subnet com tag karpenter.sh/discovery=$CLUSTER_NAME"
    echo "     Execute: aws ec2 create-tags --resources <subnet-id> --tags Key=karpenter.sh/discovery,Value=$CLUSTER_NAME"
    exit 1
  fi
else
  echo "  ⚠️  AWS CLI não encontrado, pulando verificação de tags"
fi

# Verificar logs do Karpenter
echo ""
echo "📝 Últimas linhas do log do Karpenter:"
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter --tail=5

echo ""
echo "✅ Validação completa! Karpenter está instalado corretamente."
echo ""
echo "🚀 Próximos passos:"
echo "   1. Criar NodePools: kubectl apply -f nodepool.yaml"
echo "   2. Criar EC2NodeClass: kubectl apply -f ec2nodeclass.yaml"
echo "   3. Testar provisionamento: kubectl create deployment test --image=nginx --replicas=10"
echo ""
