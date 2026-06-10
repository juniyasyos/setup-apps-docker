#!/bin/bash
set -e

# =========================
# Unified App Prepare Script
# =========================
# Reads app configuration from repos.txt and handles:
#   - Git clone/pull
#   - .env setup
#   - Local dependency installation (optional)
#   - Production env file generation
#
# Usage:
#   ./prepare.sh                    # List available apps
#   ./prepare.sh list               # List available apps
#   ./prepare.sh <app>              # Prepare single app
#   ./prepare.sh <app1> <app2>      # Prepare multiple apps
#   ./prepare.sh all                # Prepare all apps
#   ./prepare.sh <app> --no-deps    # Skip dependency install & npm build
# =========================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS_FILE="${SCRIPT_DIR}/../repos.csv"

# ============================================
# Color & Log Helpers
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error()   { echo -e "${RED}❌ $1${NC}"; }
log_header()  { echo -e "\n${CYAN}════════════════════════════════════════════${NC}"; echo -e "${CYAN}   $1${NC}"; echo -e "${CYAN}════════════════════════════════════════════${NC}"; }

# ============================================
# App Configuration from repos.csv
# ============================================
# Fields (comma-separated, no spaces around commas):
#   app_name,app_dir,repo_url,branch,has_prod_env,has_local_deps,description
#
# Example:
#   siimut,siimut,https://github.com/juniyasyos/si-imut.git,main,yes,yes,SIIMUT - Sistem Informasi Imunisasi
#   ikp,ikp,https://github.com/juniyasyos/ikp.git,main,no,no,IKP - Incident Reporting & Pelaporan Application
#   iam,iam-server,https://github.com/juniyasyos/auth-server.git,main,yes,no,IAM - Authentication & SSO Server

APP_NAMES=()
APP_DIRS=()
APP_REPOS=()
APP_BRANCHES=()
APP_HAS_PROD=()
APP_HAS_DEPS=()
APP_DESCS=()

load_all_apps() {
    APP_NAMES=(); APP_DIRS=(); APP_REPOS=(); APP_BRANCHES=()
    APP_HAS_PROD=(); APP_HAS_DEPS=(); APP_DESCS=()

    if [ ! -f "$REPOS_FILE" ]; then
        log_error "Configuration file not found: $REPOS_FILE"
        exit 1
    fi

    while IFS=',' read -r name dir repo branch has_prod has_deps desc; do
        # Skip empty lines and comments
        [ -z "$name" ] && continue
        [[ "$name" =~ ^[[:space:]]*# ]] && continue

        APP_NAMES+=("$name")
        APP_DIRS+=("$dir")
        APP_REPOS+=("$repo")
        APP_BRANCHES+=("$branch")
        APP_HAS_PROD+=("$has_prod")
        APP_HAS_DEPS+=("$has_deps")
        APP_DESCS+=("$desc")
    done < "$REPOS_FILE"
}

load_app_config() {
    local target="$1"
    load_all_apps

    for i in "${!APP_NAMES[@]}"; do
        if [ "${APP_NAMES[$i]}" = "$target" ]; then
            APP_NAME="${APP_NAMES[$i]}"
            APP_DIR="${APP_DIRS[$i]}"
            REPO_URL="${APP_REPOS[$i]}"
            BRANCH="${APP_BRANCHES[$i]}"
            HAS_PROD_ENV="${APP_HAS_PROD[$i]}"
            HAS_LOCAL_DEPS="${APP_HAS_DEPS[$i]}"
            APP_DESC="${APP_DESCS[$i]}"
            return 0
        fi
    done

    return 1
}

list_apps() {
    load_all_apps

    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════════════╗"
    echo "║                         📦  Available Applications                          ║"
    echo "╠════════╤════════════╤════════════════════════════════════════════════════════╣"
    printf "║ %-6s │ %-10s │  %-56s ║\n" "App" "Folder" "Description"
    echo "║────────┼────────────┼────────────────────────────────────────────────────────║"
    for i in "${!APP_NAMES[@]}"; do
        printf "║ %-6s │ %-10s │  %-56s ║\n" "${APP_NAMES[$i]}" "${APP_DIRS[$i]}" "${APP_DESCS[$i]}"
    done
    echo "╚════════╧════════════╧════════════════════════════════════════════════════════╝"
    echo ""
    echo "── Repository Detail ──────────────────────────────────────────────"
    for i in "${!APP_NAMES[@]}"; do
        local prod_label="–"
        local deps_label="–"
        [ "${APP_HAS_PROD[$i]}" = "yes" ] && prod_label="✓ ya" || prod_label="✗ tidak"
        [ "${APP_HAS_DEPS[$i]}" = "yes" ] && deps_label="✓ ya" || deps_label="✗ tidak"
        echo ""
        echo "  App        : ${APP_NAMES[$i]}"
        echo "  Description: ${APP_DESCS[$i]}"
        echo "  Git Repo   : ${APP_REPOS[$i]}"
        echo "  Branch     : ${APP_BRANCHES[$i]}"
        echo "  Prod Env   : ${prod_label}  (generate .env.prod.${APP_NAMES[$i]} with secrets)"
        echo "  Local Deps : ${deps_label}  (install PHP & Node deps on host)"
        echo "  Output Dir : sources/${APP_DIRS[$i]}"
    done
    echo ""
    echo "── Cara Pakai ─────────────────────────────────────────────────────"
    echo "  ./prepare.sh                    — tampilkan daftar ini"
    echo "  ./prepare.sh siimut             — prepare app siimut"
    echo "  ./prepare.sh siimut ikp         — prepare beberapa app sekaligus"
    echo "  ./prepare.sh all                — prepare semua app"
    echo "  ./prepare.sh siimut --no-deps   — skip install dependencies"
    echo ""
}

# ============================================
# Secret Generation Helpers
# ============================================

generate_app_key() {
    if command -v php &> /dev/null; then
        echo "base64:$(php -r 'echo base64_encode(random_bytes(32));')"
    else
        echo "base64:$(openssl rand -base64 32 | tr -d '\n')"
    fi
}

generate_db_password() {
    openssl rand -base64 16 | tr -d '\n'
}

generate_jwt_secret() {
    openssl rand -hex 32
}

generate_passport_keys() {
    local priv_temp pub_temp

    priv_temp=$(mktemp)
    pub_temp=$(mktemp)

    openssl genrsa -out "${priv_temp}" 2048 2>/dev/null
    openssl rsa -in "${priv_temp}" -pubout -out "${pub_temp}" 2>/dev/null

    # Read keys and escape for sed (single-line with trailing \)
    PASSPORT_PRIVATE_KEY=$(cat "${priv_temp}" | sed 's/$/\\/' | tr -d '\n' | sed 's/\\$//')
    PASSPORT_PUBLIC_KEY=$(cat "${pub_temp}" | sed 's/$/\\/' | tr -d '\n' | sed 's/\\$//')

    rm -f "${priv_temp}" "${pub_temp}"
}

# ============================================
# Phase 1 — Git Clone/Pull
# ============================================

phase_git() {
    log_header "📁 Git: ${APP_NAME}"

    local site_dir="${SCRIPT_DIR}/sources/${APP_DIR}"

    # Create site directory if not exists
    if [ ! -d "${SCRIPT_DIR}/site" ]; then
        echo "📁 Creating site directory..."
        mkdir -p "${SCRIPT_DIR}/site"
    fi

    if [ -d "${site_dir}/.git" ]; then
        echo "🔄 Repository exists, pulling latest code from branch '${BRANCH}'..."
        cd "${site_dir}"

        # IKP-style branch-aware logic
        git fetch origin
        if git rev-parse --verify "origin/${BRANCH}" > /dev/null 2>&1; then
            if git checkout "${BRANCH}" && git pull origin "${BRANCH}"; then
                log_success "Git pull successful on branch '${BRANCH}'!"
            else
                log_error "Git pull failed! Check repository status."
                exit 1
            fi
        else
            echo "⚠️  Branch '${BRANCH}' not found on origin. Using default branch..."
            if git pull origin; then
                log_success "Git pull successful!"
            else
                log_error "Git pull failed! Check repository status."
                exit 1
            fi
        fi
        cd "${SCRIPT_DIR}"
    else
        echo "📥 Repository not found, cloning from ${REPO_URL}..."
        if git clone -b "${BRANCH}" "${REPO_URL}" "${site_dir}" 2>/dev/null; then
            log_success "Git clone successful!"
        else
            # Fallback: clone default branch
            echo "⚠️  Branch '${BRANCH}' not available, cloning default branch..."
            if git clone "${REPO_URL}" "${site_dir}"; then
                log_success "Git clone successful (default branch)!"
            else
                log_error "Git clone failed! Check URL and network."
                exit 1
            fi
        fi
    fi

    log_success "Git phase complete for ${APP_NAME}"
}

# ============================================
# Phase 2 — Setup .env
# ============================================

phase_env() {
    local site_dir="${SCRIPT_DIR}/sources/${APP_DIR}"

    log_header "📋 .env: ${APP_NAME}"

    # IAM doesn't have .env.example in the same pattern
    if [ "${APP_NAME}" = "iam" ]; then
        echo "⏭️  IAM uses apps/iam as template; skipping .env copy"
        return 0
    fi

    if [ ! -f "${site_dir}/.env" ]; then
        if [ -f "${site_dir}/.env.example" ]; then
            echo "📋 Copying .env.example to .env..."
            cp "${site_dir}/.env.example" "${site_dir}/.env"
            log_success ".env file created. Please configure it as needed."
        else
            echo "⚠️  .env.example not found. Please create .env manually."
        fi
    else
        log_success ".env file already exists."
    fi
}

# ============================================
# Phase 3 — Local Dependencies & Build
# ============================================

phase_deps() {
    local no_deps="${1:-false}"

    log_header "🔧 Dependencies: ${APP_NAME}"

    if [ "${no_deps}" = "true" ]; then
        echo "⏭️  Skipping dependency install per --no-deps flag"
        return 0
    fi

    if [ "${HAS_LOCAL_DEPS}" != "yes" ]; then
        echo "⏭️  App does not require local dependencies"
        return 0
    fi

    local site_dir="${SCRIPT_DIR}/sources/${APP_DIR}"
    cd "${site_dir}"

    # Check required tools
    local missing=0
    for cmd in php composer node npm; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "$cmd not found. Please install it."
            missing=1
        fi
    done
    if [ "$missing" -eq 1 ]; then
        log_error "Missing dependencies. Exiting."
        exit 1
    fi
    log_success "Dependency tools OK"

    # Composer install
    if [ -f "composer.json" ]; then
        echo "📦 Installing Composer dependencies..."
        if composer install --no-interaction --optimize-autoloader; then
            log_success "Composer install complete"
        else
            echo "⚠️  composer install failed (continuing)"
        fi
    else
        echo "⚠️  composer.json not found, skipping Composer install"
    fi

    # npm install & build
    if [ -f "package.json" ]; then
        echo "📦 Installing npm dependencies..."
        npm install
        echo "🔨 Building frontend assets..."
        npm run build
        log_success "Frontend build complete"
    else
        echo "⚠️  package.json not found, skipping npm build"
    fi

    # Laravel-specific cache & publish
    if [ -f "artisan" ]; then
        echo "🔍 Laravel setup detected, running cache commands..."
        php artisan config:cache --quiet || echo "⚠️  config:cache failed (continuing)"
        php artisan route:cache --quiet || echo "⚠️  route:cache failed (continuing)"
        php artisan view:cache --quiet || echo "⚠️  view:cache failed (continuing)"
        echo "📦 Publishing Livewire assets..."
        php artisan livewire:publish --assets --quiet || echo "⚠️  livewire:publish failed (continuing)"
        log_success "Livewire assets published"
    fi

    cd "${SCRIPT_DIR}"
    log_success "Dependency phase complete for ${APP_NAME}"
}

# ============================================
# Phase 4 — Production Environment Generation
# ============================================

phase_prod_env() {
    log_header "🔐 Production Env: ${APP_NAME}"

    if [ "${HAS_PROD_ENV}" != "yes" ]; then
        echo "⏭️  App does not require production env generation"
        return 0
    fi

    local prod_env_file="${SCRIPT_DIR}/apps/prod.${APP_NAME}"

    # Check if production .env already exists
    if [ -f "${prod_env_file}" ] && [ ! -t 0 ]; then
        # Non-interactive mode: just skip
        echo "⏭️  ${prod_env_file} already exists and not in interactive mode; skipping."
        return 0
    elif [ -f "${prod_env_file}" ]; then
        echo "⚠️  ${prod_env_file} already exists."
        read -p "Do you want to regenerate secrets? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "⏭️  Skipping secret generation. Using existing ${prod_env_file}"
            return 0
        fi
    fi

    # Copy template
    if [ ! -f "${SCRIPT_DIR}/apps/${APP_NAME}/.env.example" ]; then
        log_error "Template not found: apps/${APP_NAME}/.env.example"
        exit 1
    fi

    echo "📋 Creating production env from template..."
    cp "${SCRIPT_DIR}/apps/${APP_NAME}/.env.example" "${prod_env_file}"
    log_success "Copied apps/${APP_NAME}/.env.example → ${prod_env_file}"

    echo ""
    echo "🔧 Generating secrets..."

    # Generate APP_KEY
    APP_KEY=$(generate_app_key)
    echo "  ✓ APP_KEY generated"

    # Generate DB passwords
    DB_PASSWORD=$(generate_db_password)
    echo "  ✓ DB_PASSWORD generated"
    MYSQL_ROOT_PASSWORD=$(generate_db_password)
    echo "  ✓ MYSQL_ROOT_PASSWORD generated"

    # Temp file for safe replacement
    local temp_file="${prod_env_file}.tmp"
    cp "${prod_env_file}" "${temp_file}"

    sed -i "s|^APP_KEY=.*|APP_KEY=${APP_KEY}|" "${temp_file}"
    sed -i "s|^MYSQL_PASSWORD=.*|MYSQL_PASSWORD=${DB_PASSWORD}|" "${temp_file}"
    sed -i "s|^MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}|" "${temp_file}"

    # App-specific secrets
    case "${APP_NAME}" in
        iam)
            # JWT secret
            IAM_JWT_SECRET=$(generate_jwt_secret)
            echo "  ✓ IAM_JWT_SECRET generated"
            sed -i "s|^IAM_JWT_SECRET=.*|IAM_JWT_SECRET=${IAM_JWT_SECRET}|" "${temp_file}"

            # Passport RSA keys
            echo "  ⏳ Generating Passport RSA keys (this may take a moment)..."
            generate_passport_keys

            # Delete old passport key blocks, then append new keys
            sed -i '/^PASSPORT_PRIVATE_KEY=/,/^-----END PRIVATE KEY-----/d' "${temp_file}"
            sed -i '/^PASSPORT_PUBLIC_KEY=/,/^-----END PUBLIC KEY-----/d' "${temp_file}"
            # Append new keys at the end of file
            {
              echo ""
              echo "PASSPORT_PRIVATE_KEY=\"${PASSPORT_PRIVATE_KEY}\""
              echo "PASSPORT_PUBLIC_KEY=\"${PASSPORT_PUBLIC_KEY}\""
            } >> "${temp_file}"
            echo "  ✓ Passport RSA keys generated"
            ;;

        siimut)
            # Sync IAM_JWT_SECRET from IAM's prod env if available
            if [ -f "${SCRIPT_DIR}/apps/prod.iam" ]; then
                local jwt
                jwt=$(grep '^IAM_JWT_SECRET=' "${SCRIPT_DIR}/apps/prod.iam" | cut -d '=' -f 2)
                if [ -n "$jwt" ]; then
                    IAM_JWT_SECRET="$jwt"
                    echo "  ✓ IAM_JWT_SECRET synced from apps/prod.iam"
                else
                    IAM_JWT_SECRET=$(generate_jwt_secret)
                    echo "  ⚠️  Could not parse IAM_JWT_SECRET from .env.prod.iam, generated new one"
                fi
            else
                IAM_JWT_SECRET=$(generate_jwt_secret)
                echo "  ⚠️  apps/prod.iam not found, generating new IAM_JWT_SECRET"
                echo "      (Recommend running ./prepare.sh iam first!)"
            fi
            sed -i "s|^IAM_JWT_SECRET=.*|IAM_JWT_SECRET=${IAM_JWT_SECRET}|" "${temp_file}"
            ;;
    esac

    mv "${temp_file}" "${prod_env_file}"
    log_success "Secrets updated in ${prod_env_file}"
    echo ""
    echo "⚠️  IMPORTANT: This file is in .gitignore - DO NOT commit!"
}

# ============================================
# Prepare Single App
# ============================================

prepare_app() {
    local target="$1"
    local no_deps="${2:-false}"

    if ! load_app_config "$target"; then
        log_error "App '${target}' tidak dikenal!"
        echo ""
        echo "App yang tersedia:"
        for i in "${!APP_NAMES[@]}"; do
            echo "  • ${APP_NAMES[$i]} — ${APP_DESCS[$i]}"
        done
        echo ""
        echo "Coba: ./prepare.sh list"
        exit 1
    fi

    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ 📦 ${APP_NAME} — ${APP_DESC}"
    echo "├─────────────────────────────────────────────────────────────┤"
    echo "│ Repo : ${REPO_URL}"
    echo "│ Cabang : ${BRANCH}"
    echo "│ Tujuan : sources/${APP_DIR}"
    echo "└─────────────────────────────────────────────────────────────┘"

    phase_git
    phase_env
    phase_deps "${no_deps}"
    phase_prod_env

    echo ""
    log_success "✅ ${APP_NAME} prepared successfully!"
}

# ============================================
# Main
# ============================================

main() {
    # No args or "list" → show available apps
    if [ $# -eq 0 ] || [ "$1" = "list" ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        list_apps
        exit 0
    fi

    # Parse args: collect apps and flags
    local apps=()
    local no_deps=false

    for arg in "$@"; do
        case "$arg" in
            --no-deps|--no-dependencies)
                no_deps=true
                ;;
            -h|--help)
                list_apps
                exit 0
                ;;
            *)
                apps+=("$arg")
                ;;
        esac
    done

    # "all" → prepare all apps
    if [ "${apps[*]}" = "all" ]; then
        load_all_apps
        apps=("${APP_NAMES[@]}")
    fi

    # Run prepare for each app
    for app in "${apps[@]}"; do
        prepare_app "$app" "$no_deps"
    done

    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ ✅  Semua aplikasi siap digunakan!                          │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""

    # Show next steps hint
    echo "Langkah selanjutnya:"
    if [ -f "${SCRIPT_DIR./scripts/build.sh" ]; then
        echo "  • Build Docker images:  ./scripts/build.sh [app]"
    fi
    if ls "${SCRIPT_DIR}"/apps/prod.* 1>/dev/null 2>&1; then
        echo "  • File production .env sudah dibuat di folder env/ (JANGAN di-commit!)"
    fi
    echo ""
}

main "$@"
