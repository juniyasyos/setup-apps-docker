#!/bin/bash

####################################################################################################
# Multi-App Build & Push to Docker Hub Script
# 
# Purpose: Build SIIMUT, IKP, IAM Server, and LMS App images, tag them, and push to Docker Hub
# Usage:
#   ./build.sh                   # Build SIIMUT only
#   ./build.sh push              # Build SIIMUT and push
#   ./build.sh ikp push          # Build IKP and push
#   ./build.sh iam push          # Build IAM Server and push
#   ./build.sh lms push          # Build LMS App and push
#   ./build.sh all push          # Build all apps and push
#   VERSION=v1.0.0 ./build.sh push  # Build specific version
#
# Configuration:
#   - DOCKER_HUB_USER: Set in environment or defaults to 'juni'
#   - VERSION: Read from ./VERSION file or environment variable
####################################################################################################

set -e

# ============================================
# Configuration
# ============================================
DOCKER_HUB_USER="${DOCKER_HUB_USER:-}"
COMPOSE_FILE="compose/build.yml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect Docker Hub username if not explicitly provided
if [ -z "$DOCKER_HUB_USER" ] && [ -f "$HOME/.docker/config.json" ]; then
    DOCKER_HUB_USER=$(python3 - <<'PY'
import json, os, base64
path = os.path.expanduser('~/.docker/config.json')
try:
    cfg = json.load(open(path))
    auths = cfg.get('auths', {})
    for registry, data in auths.items():
        auth = data.get('auth')
        if auth:
            decoded = base64.b64decode(auth).decode('utf-8', errors='ignore')
            if ':' in decoded:
                print(decoded.split(':', 1)[0])
                break
except Exception:
    pass
PY
)
fi

DOCKER_HUB_USER="${DOCKER_HUB_USER:-juniyasyos}"

# Read version: ENV VAR > VERSION file > 'latest'
if [ -z "$VERSION" ]; then
    if [ -f "$SCRIPT_DIR/VERSION" ]; then
        VERSION=$(cat "$SCRIPT_DIR/VERSION" | tr -d '[:space:]')
    else
        VERSION="latest"
    fi
fi

# Per-service version overrides can be set with environment variables.
SIIMUT_VERSION="v2.0.0"
IKP_VERSION="v1.0.0"
IAM_VERSION="v1.0.0"
LMS_VERSION="v1.0.0"
# SIIMUT_VERSION="${SIIMUT_VERSION:-$VERSION}"
# IKP_VERSION="${IKP_VERSION:-$VERSION}"
# IAM_VERSION="${IAM_VERSION:-$VERSION}"

normalize_target() {
    case "$1" in
        siimut) echo "siimut" ;;
        ikp) echo "ikp" ;;
        iam|iam-server|iamserver) echo "iam-server" ;;
        lms|lms-app|lmsapp) echo "lms-app" ;;
        all) echo "all" ;;
        build|tag|push|help|--help|-h) echo "siimut" ;;
        "") echo "siimut" ;;
        *) echo "" ;;
    esac
}

ACTION="${1:-}"
if [[ "$ACTION" =~ ^(build|tag|push|help|--help|-h)$ ]]; then
    TARGET="siimut"
    COMMAND="$ACTION"
elif [ -z "${2:-}" ]; then
    TARGET="$ACTION"
    COMMAND="build"
else
    TARGET="$ACTION"
    COMMAND="$2"
fi

TARGET="$(normalize_target "$TARGET")"
if [ -z "$TARGET" ]; then
    echo ""
    log_error "Unknown app target: ${1:-<none>}"
    echo ""
    show_help
    exit 1
fi

if [ "$TARGET" = "all" ]; then
    SELECTED_SERVICES=(siimut ikp iam-server lms-app)
else
    SELECTED_SERVICES=($TARGET)
fi

# ============================================
# Helpers
# ============================================

service_version() {
    case "$1" in
        siimut)
            echo "$SIIMUT_VERSION"
            ;;
        ikp)
            echo "$IKP_VERSION"
            ;;
        iam-server)
            echo "$IAM_VERSION"
            ;;
        lms-app)
            echo "$LMS_VERSION"
            ;;
        *)
            echo "$VERSION"
            ;;
    esac
}

service_image() {
    echo "$1:$(service_version "$1")"
}

docker_hub_image_versioned() {
    echo "$DOCKER_HUB_USER/$1:$(service_version "$1")"
}

docker_hub_image_latest() {
    echo "$DOCKER_HUB_USER/$1:latest"
}

# ============================================
# Colors for output
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# Functions
# ============================================

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_config() {
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║  Docker Build Configuration                ║"
    echo "╠════════════════════════════════════════════╣"
    echo "║  Docker Hub User:  $DOCKER_HUB_USER"
    echo "║  Target App:       $TARGET"
    echo "║  Selected Apps:    ${SELECTED_SERVICES[*]}"
    echo "║  Default Version:  $VERSION"
    echo "║  SIIMUT Version:   $SIIMUT_VERSION"
    echo "║  IKP Version:      $IKP_VERSION"
    echo "║  IAM Version:      $IAM_VERSION"
    echo "║  LMS Version:      $LMS_VERSION"
    echo "║  Compose File:     $COMPOSE_FILE"
    echo "║  Command:          $COMMAND"
    echo "╚════════════════════════════════════════════╝"
    echo ""
}

build_image() {
    log_info "Building ${SELECTED_SERVICES[*]} from $COMPOSE_FILE..."

    if [ "$TARGET" = "all" ]; then
        if SIIMUT_VERSION="$SIIMUT_VERSION" IKP_VERSION="$IKP_VERSION" IAM_VERSION="$IAM_VERSION" LMS_VERSION="$LMS_VERSION" \
            docker compose -f "$SCRIPT_DIR/$COMPOSE_FILE" build; then
            log_success "Build completed successfully"
            return 0
        fi
    else
        if SIIMUT_VERSION="$SIIMUT_VERSION" IKP_VERSION="$IKP_VERSION" IAM_VERSION="$IAM_VERSION" LMS_VERSION="$LMS_VERSION" \
            docker compose -f "$SCRIPT_DIR/$COMPOSE_FILE" build "${SELECTED_SERVICES[@]}"; then
            log_success "Build completed successfully"
            return 0
        fi
    fi

    log_error "Build failed"
    return 1
}

tag_image() {
    log_info "Tagging images..."

    for svc in "${SELECTED_SERVICES[@]}"; do
        LOCAL_IMAGE="$(service_image "$svc")"
        DOCKER_HUB_IMAGE_VERSIONED="$(docker_hub_image_versioned "$svc")"
        DOCKER_HUB_IMAGE_LATEST="$(docker_hub_image_latest "$svc")"

        if docker tag "$LOCAL_IMAGE" "$DOCKER_HUB_IMAGE_VERSIONED"; then
            log_success "Tagged: $LOCAL_IMAGE → $DOCKER_HUB_IMAGE_VERSIONED"
        else
            log_error "Failed to tag image with version: $LOCAL_IMAGE"
            return 1
        fi

        if docker tag "$LOCAL_IMAGE" "$DOCKER_HUB_IMAGE_LATEST"; then
            log_success "Tagged: $LOCAL_IMAGE → $DOCKER_HUB_IMAGE_LATEST"
        else
            log_error "Failed to tag image as latest: $LOCAL_IMAGE"
            return 1
        fi
    done

    return 0
}

verify_docker_login() {
    log_info "Verifying Docker Hub authentication..."

    if docker info 2>/dev/null | grep -q "Username:"; then
        log_success "Docker Hub authentication verified"
        return 0
    fi

    if [ -f "$HOME/.docker/config.json" ] && grep -q '"https://index.docker.io/v1/"' "$HOME/.docker/config.json"; then
        log_success "Docker Hub authentication verified via config file"
        return 0
    fi

    log_warn "Not logged in to Docker Hub"
    log_info "Please login first:"
    log_info "  docker login"
    return 1
}

push_image() {
    log_info "Pushing images to Docker Hub..."

    if ! verify_docker_login; then
        log_error "Cannot push without Docker Hub login"
        return 1
    fi

    for svc in "${SELECTED_SERVICES[@]}"; do
        IMAGE_VERSIONED="$(docker_hub_image_versioned "$svc")"
        IMAGE_LATEST="$(docker_hub_image_latest "$svc")"

        if docker push "$IMAGE_VERSIONED"; then
            log_success "Pushed: $IMAGE_VERSIONED"
        else
            log_error "Failed to push $IMAGE_VERSIONED"
            return 1
        fi

        if docker push "$IMAGE_LATEST"; then
            log_success "Pushed: $IMAGE_LATEST"
        else
            log_error "Failed to push $IMAGE_LATEST"
            return 1
        fi
    done

    return 0
}

show_help() {
    cat << EOF
╔════════════════════════════════════════════════════════════════╗
║         Build & Docker Hub Push Tool for Applications          ║
╚════════════════════════════════════════════════════════════════╝

USAGE:
    ./build.sh [APP] [COMMAND]

APPS:
    siimut               Build SIIMUT image (default)
    ikp                  Build IKP image
    iam                  Build IAM Server image
    lms                  Build LMS App image
    all                  Build all images

COMMANDS:
    build                Build image only (default)
    tag                  Build and tag for Docker Hub
    push                 Build, tag, and push to Docker Hub
    help                 Show this help message

EXAMPLES:
    # Build SIIMUT image only
    ./build.sh

    # Build and push SIIMUT image
    DOCKER_HUB_USER=juniyasyos VERSION=v1.0.1 ./build.sh push

    # Build and push IKP image
    DOCKER_HUB_USER=juniyasyos VERSION=v1.0.1 ./build.sh ikp push

    # Build and push IAM Server image
    DOCKER_HUB_USER=juniyasyos VERSION=v1.0.1 ./build.sh iam push

    # Build and push LMS App image
    DOCKER_HUB_USER=juniyasyos VERSION=v1.0.1 ./build.sh lms push

    # Build all 4 images with separate versions and push
    SIIMUT_VERSION=v3.1.0 IKP_VERSION=v1.3.0 IAM_VERSION=v2.1.0 LMS_VERSION=v1.0.0 DOCKER_HUB_USER=juniyasyos ./build.sh all push

ENVIRONMENT VARIABLES:
    DOCKER_HUB_USER        Docker Hub username (default: detected from Docker login, or 'juni' if unknown)
    VERSION                Default image version (default: read from VERSION file)
    SIIMUT_VERSION         Optional per-service version for SIIMUT
    IKP_VERSION            Optional per-service version for IKP
    IAM_VERSION            Optional per-service version for IAM Server
    LMS_VERSION            Optional per-service version for LMS App

CONFIGURATION FILES:
    VERSION                Contains version string (e.g., v1.0.0)
    compose/build.yml  Build manifest

NOTES:
    - VERSION file should contain only version string (e.g., v1.0.0)
    - Requires Docker daemon running
    - For push: requires 'docker login' to be successful
    - Images are tagged as:
        * Local: <app>:<per-service-version>
        * Docker Hub: DOCKER_HUB_USER/<app>:<per-service-version>
        * Docker Hub: DOCKER_HUB_USER/<app>:latest

╔════════════════════════════════════════════════════════════════╗
EOF
}

# ============================================
# Main Execution
# ============================================

print_config

case "$COMMAND" in
    build)
        log_info "Mode: BUILD ONLY"
        build_image
        ;;
    tag)
        log_info "Mode: BUILD & TAG"
        build_image && tag_image
        ;;
    push)
        log_info "Mode: BUILD, TAG & PUSH"
        build_image && tag_image && push_image
        ;;
    help|--help|-h)
        show_help
        exit 0
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        echo ""
        show_help
        exit 1
        ;;
esac

if [ $? -eq 0 ]; then
    echo ""
    log_success "Build process completed successfully!"
    echo ""
    echo "Next steps:"
    case "$COMMAND" in
        build)
            echo "  • Tag image:     ./build.sh tag"
            echo "  • Push to Docker Hub: ./build.sh push"
            ;;
        tag)
            echo "  • Push to Docker Hub: ./build.sh push"
            ;;
        push)
            echo "  • Deploy: VERSION=$VERSION docker-compose -f compose.yml pull"
            echo "  • Run:    VERSION=$VERSION docker-compose -f compose.yml up -d"
            ;;
    esac
    echo ""
else
    echo ""
    log_error "Build process failed!"
    exit 1
fi
