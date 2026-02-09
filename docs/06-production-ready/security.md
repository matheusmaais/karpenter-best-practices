# Segurança do Karpenter

## Princípios

1. **Least Privilege**: IAM roles com permissões mínimas
2. **IRSA**: Sem credenciais estáticas
3. **IMDSv2**: Obrigatório em todos os nós
4. **Encryption**: Volumes sempre criptografados
5. **Network Isolation**: Security groups restritivos

## IAM Best Practices

### Karpenter Controller (IRSA)

**Permissões mínimas necessárias:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:CreateFleet",
        "ec2:CreateLaunchTemplate",
        "ec2:CreateTags",
        "ec2:DescribeInstances",
        "ec2:DescribeInstanceTypes",
        "ec2:DescribeInstanceTypeOfferings",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeSubnets",
        "ec2:DescribeSecurityGroups",
        "ec2:DescribeImages",
        "ec2:DescribeLaunchTemplates",
        "ec2:DescribeSpotPriceHistory",
        "ec2:TerminateInstances",
        "ec2:DeleteLaunchTemplate"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl"
      ],
      "Resource": "arn:aws:sqs:*:*:*Karpenter*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:PassRole"
      ],
      "Resource": "arn:aws:iam::*:role/KarpenterNode*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "pricing:GetProducts"
      ],
      "Resource": "*"
    }
  ]
}
```

### Node IAM Role

**Policies necessárias:**
- `AmazonEKSWorkerNodePolicy`
- `AmazonEC2ContainerRegistryReadOnly`
- `AmazonEKS_CNI_Policy`

**Terraform:**

```hcl
module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"
  
  # Cria role automaticamente com permissões corretas
  create_node_iam_role = true
  node_iam_role_name   = "${var.cluster_name}-karpenter-node"
}
```

### Trust Relationship (IRSA)

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/oidc.eks.REGION.amazonaws.com/id/OIDC_ID"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:sub": "system:serviceaccount:karpenter:karpenter",
          "oidc.eks.REGION.amazonaws.com/id/OIDC_ID:aud": "sts.amazonaws.com"
        }
      }
    }
  ]
}
```

## IMDSv2 Enforcement

### Por que IMDSv2?

- ✅ Protege contra SSRF attacks
- ✅ Requer token de sessão
- ✅ Hop limit configurável

### Configuração

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: secure
spec:
  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 2  # Limita a containers
    httpTokens: required        # ← IMDSv2 obrigatório
```

**Validar:**

```bash
# SSH no nó e testar
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/
```

## Encryption

### EBS Volumes

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: secure
spec:
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 50Gi
        volumeType: gp3
        encrypted: true              # ← Sempre criptografado
        kmsKeyID: "arn:aws:kms:..."  # Opcional: KMS key customizada
        deleteOnTermination: true
```

### Secrets Encryption

```bash
# Habilitar encryption no EKS
aws eks update-cluster-config \
  --name my-cluster \
  --encryption-config '[{"resources":["secrets"],"provider":{"keyArn":"arn:aws:kms:..."}}]'
```

## Network Security

### Security Groups

**Regras mínimas:**

```hcl
# Ingress: Permitir comunicação entre nós
resource "aws_security_group_rule" "node_to_node" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.node.id
}

# Ingress: Permitir control plane -> nodes
resource "aws_security_group_rule" "control_plane_to_node" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.control_plane.id
}

# Egress: Permitir tráfego de saída
resource "aws_security_group_rule" "node_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.node.id
  cidr_blocks       = ["0.0.0.0/0"]
}
```

### Network Policies

```yaml
# Restringir tráfego entre pods
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: default
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

## Pod Security

### Pod Security Standards

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Security Context

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: app
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            runAsNonRoot: true
            capabilities:
              drop: ["ALL"]
```

## Audit Logging

### EKS Control Plane Logs

```bash
# Habilitar audit logs
aws eks update-cluster-config \
  --name my-cluster \
  --logging '{"clusterLogging":[{"types":["audit","authenticator"],"enabled":true}]}'
```

### Karpenter Audit

```bash
# Ver ações do Karpenter
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | grep -i "created\|deleted\|terminated"
```

## Compliance

### CIS Kubernetes Benchmark

Recomendações aplicáveis ao Karpenter:

1. ✅ IRSA ao invés de credenciais estáticas
2. ✅ IMDSv2 obrigatório
3. ✅ Volumes criptografados
4. ✅ Security groups restritivos
5. ✅ Pod Security Standards
6. ✅ Network Policies
7. ✅ Audit logging habilitado

### HIPAA/PCI-DSS

Considerações adicionais:

- ✅ KMS keys customizadas para encryption
- ✅ VPC endpoints (sem tráfego internet)
- ✅ CloudTrail para auditoria
- ✅ GuardDuty para detecção de ameaças
- ✅ Config Rules para compliance

## Secrets Management

### Evitar Secrets em User Data

```yaml
# ❌ RUIM - secret em user data
spec:
  userData: |
    #!/bin/bash
    export API_KEY=secret123

# ✅ BOM - usar External Secrets ou Secrets Manager
spec:
  userData: |
    #!/bin/bash
    export API_KEY=$(aws secretsmanager get-secret-value --secret-id api-key --query SecretString --output text)
```

## Monitoring de Segurança

### Alertas Recomendados

1. **IAM role assumido por entidade não autorizada**
2. **Nós criados fora das subnets permitidas**
3. **Security group modificado**
4. **IMDSv1 usado** (deveria ser v2)
5. **Volume não criptografado criado**

### CloudTrail Events

```bash
# Ver ações do Karpenter no CloudTrail
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=Username,AttributeValue=karpenter \
  --max-results 50
```

## Hardening Checklist

- [ ] IRSA configurado (sem credenciais estáticas)
- [ ] IMDSv2 obrigatório
- [ ] Volumes criptografados
- [ ] Security groups com least privilege
- [ ] Network Policies configuradas
- [ ] Pod Security Standards enforced
- [ ] Audit logging habilitado
- [ ] Secrets em Secrets Manager (não em user data)
- [ ] KMS keys customizadas (se compliance)
- [ ] GuardDuty habilitado
- [ ] CloudTrail monitorando ações do Karpenter

## Referências

- [EKS Security Best Practices](https://aws.github.io/aws-eks-best-practices/security/docs/)
- [IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)
- [IMDSv2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html)
- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
