#!/bin/bash
# Validate Helm chart rendering for all services and environments
# PETPLAT-110: Test Helm template rendering and validate output

set -euo pipefail

CHART_PATH="helm/petclinic-service"
SERVICES=("config-server" "discovery-server" "api-gateway" "customers-service" "visits-service" "vets-service" "genai-service" "admin-server")
ENVIRONMENTS=("dev")
ACCOUNT_ID="569144120198"
REGION="eu-central-1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Helm Chart Validation ==="
echo ""

# Step 1: helm lint
echo "[1/3] Running helm lint..."
if helm lint "$CHART_PATH" > /tmp/helm-lint.log 2>&1; then
    echo -e "${GREEN}✓ helm lint passed${NC}"
else
    echo -e "${RED}✗ helm lint failed${NC}"
    cat /tmp/helm-lint.log
    exit 1
fi
echo ""

# Step 2: helm template for all services and environments
echo "[2/3] Testing helm template rendering..."
failed_count=0

for env in "${ENVIRONMENTS[@]}"; do
    for service in "${SERVICES[@]}"; do
        echo -n "  $service ($env): "

        if helm template "$service" "$CHART_PATH" \
            -f "helm-values/$service.yaml" \
            -f "helm-values/$env.yaml" \
            --namespace "petclinic-$env" \
            --set "image.repository=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/petclinic-$env/$service" \
            --set "image.tag=v1.0.0" > "/tmp/$service-$env.yaml" 2>&1; then

            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
            cat "/tmp/$service-$env.yaml"
            ((failed_count++))
        fi
    done
done

if [ $failed_count -gt 0 ]; then
    echo -e "${RED}$failed_count service(s) failed to render${NC}"
    exit 1
fi
echo ""

# Step 3: Validate rendered YAML (basic syntax check)
echo "[3/3] Validating rendered YAML syntax..."
syntax_errors=0

for env in "${ENVIRONMENTS[@]}"; do
    for service in "${SERVICES[@]}"; do
        if ! grep -q "^apiVersion:" "/tmp/$service-$env.yaml"; then
            echo -e "${RED}✗ $service-$env.yaml missing apiVersion${NC}"
            ((syntax_errors++))
        fi
    done
done

if [ $syntax_errors -eq 0 ]; then
    echo -e "${GREEN}✓ All rendered templates have valid YAML structure${NC}"
else
    echo -e "${RED}$syntax_errors template(s) have validation errors${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=== All validations passed ===${NC}"
echo ""
echo "Summary:"
echo "  - Services validated: ${#SERVICES[@]}"
echo "  - Environments: ${#ENVIRONMENTS[@]}"
echo "  - Total templates tested: $((${#SERVICES[@]} * ${#ENVIRONMENTS[@]}))"
