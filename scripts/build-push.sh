#!/usr/bin/env bash
# Build ARM64 Docker images for all petclinic services and push to ECR.
#
# Usage:
#   ./build-push.sh --repo-dir /path/to/spring-petclinic-microservices [options]
#
# Options:
#   --repo-dir DIR     Path to spring-petclinic-microservices checkout (required)
#   --env      ENV     Target environment: dev or prod (default: dev)
#   --tag      TAG     Image tag (default: 7-char git SHA of app repo)
#   --region   REGION  AWS region (default: eu-central-1)
#   --service  NAME    Build only this service (default: all 8)
#   --no-push          Build but do not push to ECR (useful for local smoke tests)
#   --skip-mvn         Skip Maven build, assume JARs already exist in target/
#
# Design:
#   Maven builds all JARs first (one pass, faster than per-service).
#   docker buildx then builds each service image for linux/arm64, using the
#   shared docker/Dockerfile with ARTIFACT_NAME and EXPOSED_PORT build args.
#   ARTIFACT_NAME is resolved from the actual JAR in target/ to avoid hardcoding
#   the project version.

set -euo pipefail

# ── Service metadata ──────────────────────────────────────────────────────────
# Ports match docker.image.exposed.port in each service's pom.xml.
# EXPOSE is cosmetic — K8s Service manifests control actual routing.
declare -A SERVICE_PORTS=(
  [config-server]=8888
  [discovery-server]=8761
  [api-gateway]=8081
  [customers-service]=8081
  [visits-service]=8081
  [vets-service]=8081
  [genai-service]=8081
  [admin-server]=9090
)

# Ordered list used for build sequence (config-server first for faster CI feedback).
ORDERED_SERVICES=(
  config-server
  discovery-server
  api-gateway
  customers-service
  visits-service
  vets-service
  genai-service
  admin-server
)

# ── Argument parsing ──────────────────────────────────────────────────────────
REPO_DIR=""
ENV="dev"
TAG=""
REGION="eu-central-1"
PUSH=true
SKIP_MVN=false
SELECTED_SERVICE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-dir)  REPO_DIR="$2";           shift 2 ;;
    --env)       ENV="$2";                shift 2 ;;
    --tag)       TAG="$2";                shift 2 ;;
    --region)    REGION="$2";             shift 2 ;;
    --service)   SELECTED_SERVICE="$2";   shift 2 ;;
    --no-push)   PUSH=false;              shift   ;;
    --skip-mvn)  SKIP_MVN=true;           shift   ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ── Validation ────────────────────────────────────────────────────────────────
if [[ -z "${REPO_DIR}" ]]; then
  echo "ERROR: --repo-dir is required" >&2
  echo "  Example: $0 --repo-dir /path/to/spring-petclinic-microservices" >&2
  exit 1
fi

REPO_DIR=$(realpath "${REPO_DIR}")

if [[ ! -f "${REPO_DIR}/mvnw" ]]; then
  echo "ERROR: ${REPO_DIR} does not look like a spring-petclinic-microservices checkout (mvnw not found)" >&2
  exit 1
fi

if [[ ! -f "${REPO_DIR}/docker/Dockerfile" ]]; then
  echo "ERROR: ${REPO_DIR}/docker/Dockerfile not found" >&2
  exit 1
fi

if [[ -n "${SELECTED_SERVICE}" ]] && [[ -z "${SERVICE_PORTS[${SELECTED_SERVICE}]+set}" ]]; then
  echo "ERROR: Unknown service '${SELECTED_SERVICE}'. Valid services: ${ORDERED_SERVICES[*]}" >&2
  exit 1
fi

# ── Resolve tag from app repo git SHA ────────────────────────────────────────
if [[ -z "${TAG}" ]]; then
  TAG=$(git -C "${REPO_DIR}" rev-parse --short=7 HEAD 2>/dev/null || echo "local")
fi

# ── Resolve ECR registry ─────────────────────────────────────────────────────
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

echo "================================================="
echo "  Environment : ${ENV}"
echo "  Image tag   : ${TAG}"
echo "  Registry    : ${REGISTRY}"
echo "  Platform    : linux/arm64"
echo "  Push        : ${PUSH}"
echo "  App repo    : ${REPO_DIR}"
echo "================================================="

# ── ECR login ─────────────────────────────────────────────────────────────────
if [[ "${PUSH}" == "true" ]]; then
  echo ""
  echo "==> Logging in to ECR..."
  aws ecr get-login-password --region "${REGION}" \
    | docker login --username AWS --password-stdin "${REGISTRY}"
fi

# ── QEMU + buildx setup ───────────────────────────────────────────────────────
# Required on x86 runners for cross-compiling to linux/arm64.
# Safe to run on ARM64 hosts — binfmt install is a no-op for native platform.
echo ""
echo "==> Configuring docker buildx for linux/arm64..."
docker run --rm --privileged tonistiigi/binfmt --install arm64 2>/dev/null || true

if ! docker buildx inspect "${BUILDER_NAME:-petclinic-arm64}" &>/dev/null; then
  docker buildx create --name "petclinic-arm64" --driver docker-container --use
else
  docker buildx use "petclinic-arm64"
fi
docker buildx inspect --bootstrap 1>/dev/null

# ── Maven build ───────────────────────────────────────────────────────────────
if [[ "${SKIP_MVN}" == "false" ]]; then
  echo ""
  echo "==> Building all service JARs with Maven (tests skipped)..."
  cd "${REPO_DIR}"
  ./mvnw package -DskipTests --no-transfer-progress
  cd - >/dev/null
fi

# ── Build and push images ─────────────────────────────────────────────────────
SERVICES_TO_BUILD=("${ORDERED_SERVICES[@]}")
if [[ -n "${SELECTED_SERVICE}" ]]; then
  SERVICES_TO_BUILD=("${SELECTED_SERVICE}")
fi

echo ""
FAILED=()

for SERVICE in "${SERVICES_TO_BUILD[@]}"; do
  MODULE_DIR="${REPO_DIR}/spring-petclinic-${SERVICE}"

  if [[ ! -d "${MODULE_DIR}" ]]; then
    echo "WARNING: Module directory not found: ${MODULE_DIR} — skipping ${SERVICE}"
    continue
  fi

  # Resolve ARTIFACT_NAME from the built JAR in target/
  # Excludes -sources and -tests JARs; picks the main executable JAR.
  JAR=$(find "${MODULE_DIR}/target" -maxdepth 1 -name "*.jar" \
          ! -name "*-sources.jar" \
          ! -name "*-tests.jar"   \
          ! -name "*-javadoc.jar" \
          2>/dev/null | sort | tail -1)

  if [[ -z "${JAR}" ]]; then
    echo "ERROR: No JAR found in ${MODULE_DIR}/target — did Maven run successfully?" >&2
    FAILED+=("${SERVICE}")
    continue
  fi

  ARTIFACT_NAME=$(basename "${JAR}" .jar)
  EXPOSED_PORT="${SERVICE_PORTS[${SERVICE}]}"
  IMAGE="${REGISTRY}/petclinic-${ENV}/${SERVICE}:${TAG}"

  echo "==> [${SERVICE}]"
  echo "    Artifact : ${ARTIFACT_NAME}.jar"
  echo "    Image    : ${IMAGE}"

  BUILDX_ARGS=(
    --platform "linux/arm64"
    --file    "${REPO_DIR}/docker/Dockerfile"
    --build-arg "ARTIFACT_NAME=${ARTIFACT_NAME}"
    --build-arg "EXPOSED_PORT=${EXPOSED_PORT}"
    --tag     "${IMAGE}"
  )

  if [[ "${PUSH}" == "true" ]]; then
    BUILDX_ARGS+=(--push)
  else
    # Output to a local OCI tarball so the build is fully exercised without pushing.
    BUILDX_ARGS+=(--output "type=oci,dest=/tmp/${SERVICE}-arm64.tar")
  fi

  if docker buildx build "${BUILDX_ARGS[@]}" "${MODULE_DIR}/target"; then
    echo "    OK"
  else
    echo "ERROR: Build failed for ${SERVICE}" >&2
    FAILED+=("${SERVICE}")
  fi

  echo ""
done

# ── Summary ───────────────────────────────────────────────────────────────────
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "ERROR: The following services failed to build:" >&2
  printf '  - %s\n' "${FAILED[@]}" >&2
  exit 1
fi

echo "All images built successfully."
echo "  Tag      : ${TAG}"
echo "  Registry : ${REGISTRY}/petclinic-${ENV}/"
if [[ "${PUSH}" == "false" ]]; then
  echo "  (--no-push: images written to /tmp/*-arm64.tar, not pushed to ECR)"
fi
