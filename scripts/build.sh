#!/bin/bash

####################################################################################################
# Multi-App Build & Push to Docker Hub Script
#
# Apps are discovered automatically from apps/*/app.yml at runtime.
# Each app.yml defines: name, image, version, and other metadata.
#
# Usage:
#   ./build.sh                   # Build first discovered app
#   ./build.sh siimut            # Build specific app
#   ./build.sh siimut push       # Build + tag + push
#   ./build.sh all push          # Build + tag + push ALL apps
#   VERSION=v2.0.0 ./build.sh push  # Override version for all apps
#
# Environment overrides:
#   DOCKER_HUB_USER    — Docker Hub username (auto-detected from docker login)
#   VERSION            — Override version for ALL apps
#   <APP>_VERSION      — Legacy per-app version override (e.g. SIIMUT_VERSION)
#
# Dependencies:
#   yq (recommended) for YAML parsing
#   Falls back to python3 + PyYAML, then grep/awk for flat YAML
####################################################################################################

set -e

# ============================================
# Configuration
# ============================================
DOCKER_HUB_USER="${DOCKER_HUB_USER:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_FILE="compose/build.yml"
APPS_DIR="$PROJECT_ROOT/apps"

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

# Global VERSION override from environment
VERSION="${VERSION:-}"

# ============================================
# Colors
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error()   { echo -e "${RED}❌ $1${NC}"; }

# ============================================
# YAML Reader — tries yq → python3 yaml → grep fallback
# ============================================
yaml_read() {
    local file="$1" key="$2"
    [ -f "$file" ] || return 1

    # Try yq (generic YAML processor)
    if command -v yq &>/dev/null; then
        local val
        val=$(yq -r ".${key} // \"\"" "$file" 2>/dev/null || true)
        [ -n "$val" ] && { echo "$val"; return 0; }
        return 1
    fi

    # Try python3 with PyYAML
    if python3 -c "import yaml; print('ok')" &>/dev/null 2>&1; then
        local val
        val=$(python3 -c "
import yaml, sys
with open('$file') as f:
    d = yaml.safe_load(f)
    for k in '$key'.split('.'):
        if not isinstance(d, dict):
            d = {}
            break
        d = d.get(k, {})
    v = d if not isinstance(d, dict) else ''
    if v != '' and not isinstance(v, (dict, list)):
        print(v)
" 2>/dev/null || true)
        [ -n "$val" ] && { echo "$val"; return 0; }
        return 1
    fi

    # Fallback: grep flat YAML (key: value) for simple key-value files
    local val
    val=$(grep -E "^${key}:" "$file" 2>/dev/null | head -1 | sed -E 's/^[^:]+:[[:space:]]*"?([^"]*)"?/\1/' || true)
    [ -n "$val" ] && { echo "$val"; return 0; }
    return 1
}

# ============================================
# App Discovery — reads apps/*/app.yml at runtime
# ============================================

# Get list of all app names (from app.yml `name` field)
discover_apps() {
    local apps=()
    local app_yml name has_fe fe_name
    for app_yml in "$APPS_DIR"/*/app.yml; do
        [ -f "$app_yml" ] || continue
        name=$(yaml_read "$app_yml" "name" || true)
        [ -n "$name" ] || continue
        apps+=("$name")
        
        has_fe=$(yaml_read "$app_yml" "has_frontend" | tr '[:upper:]' '[:lower:]' || true)
        if [ "$has_fe" = "true" ] || [ "$has_fe" = "yes" ] || [ "$has_fe" = "1" ]; then
            fe_name=$(yaml_read "$app_yml" "fe_name" || true)
            [ -n "$fe_name" ] && apps+=("$fe_name")
        fi
    done
    echo "${apps[@]}"
}

# Look up a key from an app's app.yml by app name
app_config() {
    local app_name="$1" key="$2"
    local app_yml="$APPS_DIR/$app_name/app.yml"
    local prefix=""

    if [ ! -f "$app_yml" ]; then
        # Fallback: search by name field or fe_name field
        local f
        for f in "$APPS_DIR"/*/app.yml; do
            [ -f "$f" ] || continue
            if [ "$(yaml_read "$f" "name" || true)" = "$app_name" ]; then
                app_yml="$f"
                break
            fi
            if [ "$(yaml_read "$f" "fe_name" || true)" = "$app_name" ]; then
                app_yml="$f"
                prefix="fe_"
                break
            fi
        done
    fi

    [ -n "$prefix" ] && key="${prefix}${key}"
    yaml_read "$app_yml" "$key" || true
}

# Get version for an app — precedence: <APP>_VERSION env > VERSION env > app.yml
get_app_version() {
    local app_name="$1"
    local env_name
    env_name="$(echo "${app_name}_VERSION" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"

    # Per-app env var (legacy, e.g. SIIMUT_VERSION)
    local val="${!env_name}"
    [ -n "$val" ] && { echo "$val"; return 0; }

    # Global VERSION env var
    [ -n "$VERSION" ] && { echo "$VERSION"; return 0; }

    # Default from app.yml
    app_config "$app_name" "version"
}

# Docker Hub image name from app.yml (e.g. juniyasyos/siimut)
get_app_image() {
    app_config "$1" "image"
}

# Compose service name = last segment of image name (e.g. iam-server from juniyasyos/iam-server)
get_compose_service() {
    local full
    full=$(get_app_image "$1")
    echo "${full##*/}"
}

resolve_app_target() {
    local target="$1"

    # Normalize to lowercase
    target=$(echo "$target" | tr '[:upper:]' '[:lower:]')

    local app_yml name dirname image_full image_short

    for app_yml in "$APPS_DIR"/*/app.yml; do
        [ -f "$app_yml" ] || continue
        name=$(yaml_read "$app_yml" "name" || true)
        [ -n "$name" ] || continue

        dirname="$(basename "$(dirname "$app_yml")")"
        image_full=$(yaml_read "$app_yml" "image" || true)
        image_short="${image_full##*/}"

        if [ "$name" = "$target" ] || [ "$dirname" = "$target" ] || [ "$image_short" = "$target" ]; then
            echo "$name"
            return 0
        fi
        
        local has_fe fe_name fe_image_full fe_image_short
        has_fe=$(yaml_read "$app_yml" "has_frontend" | tr '[:upper:]' '[:lower:]' || true)
        if [ "$has_fe" = "true" ] || [ "$has_fe" = "yes" ] || [ "$has_fe" = "1" ]; then
            fe_name=$(yaml_read "$app_yml" "fe_name" || true)
            fe_image_full=$(yaml_read "$app_yml" "fe_image" || true)
            fe_image_short="${fe_image_full##*/}"
            
            if [ "$fe_name" = "$target" ] || [ "$fe_image_short" = "$target" ]; then
                echo "$fe_name"
                return 0
            fi
        fi
    done

    return 1
}

# Resolve "all" or return matching app — prints resolved app name(s)
resolve_targets() {
    local target="$1"
    [ -z "$target" ] && target="$DEFAULT_APP"

    if [ "$target" = "all" ]; then
        discover_apps
        return 0
    fi

    local resolved
    resolved=$(resolve_app_target "$target") || true
    if [ -z "$resolved" ]; then
        return 1
    fi
    echo "$resolved"
}

# ============================================
# Helpers
# ============================================

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

# ============================================
# Core Actions
# ============================================

print_config() {
    local apps=("$@")
    echo ""
    echo "╔════════════════════════════════════════════╗"
    echo "║  Docker Build Configuration                ║"
    echo "╠════════════════════════════════════════════╣"
    echo "║  Docker Hub User:  $DOCKER_HUB_USER"
    echo "║  Target App(s):    ${apps[*]}"
    echo "║  Global Version:   ${VERSION:-<from app.yml>}"
    echo "║  Compose File:     $COMPOSE_FILE"
    echo "╚════════════════════════════════════════════╝"
    echo ""

    # Print per-app details
    for app_name in "${apps[@]}"; do
        local ver img svc
        ver=$(get_app_version "$app_name")
        img=$(get_app_image "$app_name")
        svc=$(get_compose_service "$app_name")
        printf "  %-12s  image=%-30s  version=%-12s  compose_service=%s\n" \
            "[$app_name]" "$img" "$ver" "$svc"
    done
    echo ""
}

build_images() {
    local apps=("$@")

    log_info "Building: ${apps[*]}..."

    # Build each app via docker compose
    for app_name in "${apps[@]}"; do
        local ver svc
        ver=$(get_app_version "$app_name")
        svc=$(get_compose_service "$app_name")

        # Construct env name for compose (e.g. SIIMUT_VERSION)
        local env_name
        env_name="$(echo "${app_name}_VERSION" | tr '[:lower:]' '[:upper:]' | tr '-' '_')"

        log_info "Building [$app_name] → compose service [$svc] version [$ver]..."

        if ! eval "${env_name}=\"${ver}\" docker compose -f \"$PROJECT_ROOT/$COMPOSE_FILE\" build \"$svc\""; then
            log_error "Build failed for [$app_name]"
            return 1
        fi

        log_success "Built [$app_name] successfully"
    done

    return 0
}

tag_images() {
    local apps=("$@")
    log_info "Tagging images for Docker Hub..."

    for app_name in "${apps[@]}"; do
        local ver img svc
        ver=$(get_app_version "$app_name")
        img=$(get_app_image "$app_name")
        svc=$(get_compose_service "$app_name")

        local local_image="${svc}:${ver}"
        local hub_versioned="${img}:${ver}"
        local hub_latest="${img}:latest"

        if docker tag "$local_image" "$hub_versioned"; then
            log_success "Tagged: $local_image → $hub_versioned"
        else
            log_error "Failed to tag versioned: $local_image"
            return 1
        fi

        if docker tag "$local_image" "$hub_latest"; then
            log_success "Tagged: $local_image → $hub_latest"
        else
            log_error "Failed to tag latest: $local_image"
            return 1
        fi
    done

    return 0
}

push_images() {
    local apps=("$@")
    log_info "Pushing images to Docker Hub..."

    if ! verify_docker_login; then
        log_error "Cannot push without Docker Hub login"
        return 1
    fi

    for app_name in "${apps[@]}"; do
        local ver img
        ver=$(get_app_version "$app_name")
        img=$(get_app_image "$app_name")

        local hub_versioned="${img}:${ver}"
        local hub_latest="${img}:latest"

        if docker push "$hub_versioned"; then
            log_success "Pushed: $hub_versioned"
        else
            log_error "Failed to push $hub_versioned"
            return 1
        fi

        if docker push "$hub_latest"; then
            log_success "Pushed: $hub_latest"
        else
            log_error "Failed to push $hub_latest"
            return 1
        fi
    done

    return 0
}

show_help() {
    local all_apps
    all_apps=$(discover_apps)

    cat << EOF
╔════════════════════════════════════════════════════════════════╗
║         Build & Docker Hub Push Tool for Applications          ║
╚════════════════════════════════════════════════════════════════╝

USAGE:
    ./build.sh [APP] [COMMAND]

APPS (auto-discovered from apps/*/app.yml):
EOF
    for app in $all_apps; do
        local desc
        desc=$(app_config "$app" "description" || true)
        printf "    %-20s %s\n" "$app" "${desc:-}"
    done

    cat << EOF
    all                  Build ALL apps

COMMANDS:
    build                Build image only (default)
    tag                  Build and tag for Docker Hub
    push                 Build, tag, and push to Docker Hub
    help                 Show this help message

EXAMPLES:
    ./build.sh
    ./build.sh siimut push
    ./build.sh all push
    VERSION=v2.0.0 ./build.sh push

ENVIRONMENT VARIABLES:
    DOCKER_HUB_USER      Docker Hub username (auto-detected from docker login)
    VERSION              Override version for ALL apps
    <APP>_VERSION        Per-app version override (e.g. SIIMUT_VERSION)

CONFIGURATION:
    apps/*/app.yml       App metadata (name, image, version, source_dir, ...)
    compose/build.yml    Docker Compose build manifest

NOTES:
    - Requires Docker daemon running
    - For push: requires 'docker login' to be successful
    - Images are tagged locally as <image-short>:<version>
    - Docker Hub tags: DOCKER_HUB_USER/<image>:<version> and :latest
EOF
}

APPS=()
ACTIONS=()

for arg in "$@"; do
    case "$arg" in
        build|tag|push|help|--help|-h)
            ACTIONS+=("$arg")
            ;;
        *)
            APPS+=("$arg")
            ;;
    esac
done

if [ ${#ACTIONS[@]} -eq 0 ]; then
    ACTIONS=("build")
fi

ACTION="${ACTIONS[0]}"

if [ "$ACTION" = "help" ] || [ "$ACTION" = "--help" ] || [ "$ACTION" = "-h" ]; then
    show_help
    exit 0
fi

APP_TARGETS=()
if [ ${#APPS[@]} -eq 0 ]; then
    ALL_APPS=( $(discover_apps) )
    if [ ${#ALL_APPS[@]} -eq 0 ]; then
        log_error "No apps found in $APPS_DIR/*/app.yml"
        exit 1
    fi
    APP_TARGETS=( "${ALL_APPS[0]}" )
else
    for app in "${APPS[@]}"; do
        if [ "$app" = "all" ]; then
            APP_TARGETS=( $(discover_apps) )
            break
        else
            resolved=$(resolve_targets "$app") || true
            if [ -n "$resolved" ]; then
                for r in $resolved; do
                    APP_TARGETS+=("$r")
                done
            else
                log_error "Unknown app target: $app"
                echo ""
                show_help
                exit 1
            fi
        fi
    done
fi

# ============================================
# Main
# ============================================

print_config "${APP_TARGETS[@]}"

case "$ACTION" in
    build|tag|push)
        log_info "Mode: ${ACTION^^}"
        ;;
esac

case "$ACTION" in
    build)
        build_images "${APP_TARGETS[@]}"
        ;;
    tag)
        build_images "${APP_TARGETS[@]}" && tag_images "${APP_TARGETS[@]}"
        ;;
    push)
        build_images "${APP_TARGETS[@]}" && tag_images "${APP_TARGETS[@]}" && push_images "${APP_TARGETS[@]}"
        ;;
esac

BUILD_EXIT=$?

echo ""
if [ $BUILD_EXIT -eq 0 ]; then
    log_success "Build process completed successfully!"
    echo ""
    echo "Next steps:"
    case "$ACTION" in
        build)
            echo "  • Tag image:     ./build.sh ${APP_TARGETS[0]} tag"
            echo "  • Push to Docker Hub: ./build.sh ${APP_TARGETS[0]} push"
            ;;
        tag)
            echo "  • Push to Docker Hub: ./build.sh ${APP_TARGETS[0]} push"
            ;;
        push)
            echo "  • Deploy: VERSION=$VERSION docker compose -f compose.yml pull"
            echo "  • Run:    VERSION=$VERSION docker compose -f compose.yml up -d"
            ;;
    esac
    echo ""
else
    log_error "Build process failed!"
    exit 1
fi
