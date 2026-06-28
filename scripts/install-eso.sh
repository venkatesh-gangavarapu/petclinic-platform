#!/usr/bin/env bash
# Install External Secrets Operator on the petclinic EKS cluster via Helm.
# After install, annotates the ESO service account with the IRSA role ARN
# so the ClusterSecretStore can authenticate to AWS Secrets Manager.
#
# Usage:
#   ./install-eso.sh [--env dev|prod] [--cluster NAME] [--region REGION]
#
# Prerequisites:
#   - kubectl configured for the target cluster
#   - Helm 3 installed
#   - Terraform apply completed (ESO IRSA role must exist)

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
ESO_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/petclinic-${ENV}-eso-role"

echo "================================================="
echo "  Cluster      : ${CLUSTER_NAME}"
echo "  Region       : ${REGION}"
echo "  ESO Role ARN : ${ESO_ROLE_ARN}"
echo "================================================="

kubectl cluster-info --context "$(kubectl config current-context)" >/dev/null

# Add ESO Helm repo
helm repo add external-secrets https://charts.external-secrets.io
helm repo update external-secrets

# Install ESO — annotate service account with IRSA role at install time
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${ESO_ROLE_ARN}" \
  --set webhook.port=9443 \
  --wait \
  --timeout=5m

echo ""
echo "==> External Secrets Operator installed."
kubectl get pods -n external-secrets

# Apply ClusterSecretStore
echo ""
echo "==> Applying ClusterSecretStore..."
kubectl apply -f k8s/base/external-secrets/cluster-secret-store.yaml

echo ""
echo "==> Verifying ClusterSecretStore..."
sleep 5
kubectl get clustersecretstore aws-secrets-manager
