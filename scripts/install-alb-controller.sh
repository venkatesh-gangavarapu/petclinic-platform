#!/usr/bin/env bash
# Install the AWS Load Balancer Controller on the petclinic EKS cluster via Helm.
#
# Usage:
#   ./install-alb-controller.sh [--env dev|prod] [--cluster NAME] [--region REGION]
#
# Prerequisites:
#   - kubectl configured for the target cluster
#   - Helm 3 installed
#   - AWS CLI configured with credentials that can read ECR and EKS
#   - Terraform apply completed (IRSA role must exist)

set -euo pipefail

ENV="dev"
CLUSTER_NAME="petclinic-dev"
REGION="eu-central-1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)     ENV="$2";          shift 2 ;;
    --cluster) CLUSTER_NAME="$2"; shift 2 ;;
    --region)  REGION="$2";       shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/petclinic-${ENV}-lb-controller-role"
VPC_ID=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" \
  --query 'cluster.resourcesVpcConfig.vpcId' --output text)

echo "================================================="
echo "  Cluster      : ${CLUSTER_NAME}"
echo "  Region       : ${REGION}"
echo "  VPC ID       : ${VPC_ID}"
echo "  IRSA Role    : ${ROLE_ARN}"
echo "================================================="

# Verify cluster is reachable
kubectl cluster-info --context "$(kubectl config current-context)" >/dev/null

# Add EKS Helm chart repo
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks

# Install or upgrade the controller
# ECR image repo for eu-central-1 (avoids Docker Hub rate limits)
ECR_REPO="602401143452.dkr.ecr.${REGION}.amazonaws.com/amazon/aws-load-balancer-controller"

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${ROLE_ARN}" \
  --set region="${REGION}" \
  --set vpcId="${VPC_ID}" \
  --set image.repository="${ECR_REPO}" \
  --set replicaCount=1 \
  --wait \
  --timeout=5m

echo ""
echo "==> AWS Load Balancer Controller installed."
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
