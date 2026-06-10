#!/usr/bin/env bash
set -euo pipefail

# =========================
# Unified App Prepare Script
# =========================
# Reads app configuration from repos.txt and handles:
#   - Interactive scaffolding for new apps
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
#
# For NEW apps (not in repos.csv):
#   ./prepare.sh <new-app>          # Interactive scaffolding then prepare
# =========================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPOS_FILE="${PROJECT_DIR}/repos.csv"

# ============================================
# Source libraries
# ============================================
source "${SCRIPT_DIR}/scaffold.sh"
source "${SCRIPT_DIR}/prepare/mode_dockerfile.sh"
source "${SCRIPT_DIR}/prepare/mode_clone.sh"
source "${SCRIPT_DIR}/prepare/mode_image.sh"

# ============================================
# Color & Log Helpers
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error()   { echo -e "${RED}❌ $1${NC}"; }
log_header()  { echo -e "\n${CYAN}════════════════════════════════════════════${NC}"; echo -e "${CYAN}   $1${NC}"; echo -e "${CYAN}════════════════════════════════════════════${NC}"; }

# ============================================
# App Configuration from repos.csv
# ============================================
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

# Check if app exists in repos.csv
app_exists_in_repos() {
    local target="$1"
    load_all_apps

    for i in "${!APP_NAMES[@]}"; do
        if [ "${APP_NAMES[$i]}" = "$target" ]; then
            return 0
        fi
    done
    return 1
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
        echo "  Prod Env   : ${prod_label}"
        echo "  Local Deps : ${deps_label}"
        echo "  Output Dir : site/${APP_DIRS[$i]}"
    done
    echo ""
    echo "── Cara Pakai ─────────────────────────────────────────────────────"
    echo "  ./prepare.sh                    — tampilkan daftar ini"
    echo "  ./prepare.sh siimut             — prepare app siimut"
    echo "  ./prepare.sh siimut ikp         — prepare beberapa app sekaligus"
    echo "  ./prepare.sh mynewapp           — scaffolding + prepare app baru"
    echo "  ./prepare.sh siimut --no-deps   — skip install dependencies"
    echo ""
}

# ============================================
# Interactive Mode Selection
# ============================================

show_mode_menu() {
    local app_name="$1"
    local app_desc="$2"

    echo ""
    echo "  ╔══════════════════════════════════════════════════════════╗"
    printf "  ║  📦 Prepare: %-44s║\n" "${app_name}"
    if [ -n "${app_desc}" ]; then
        # Potong deskripsi jika terlalu panjang
        local short_desc="${app_desc:0:44}"
        printf "  ║  %-56s║\n" "${short_desc}"
    fi
    echo "  ╠══════════════════════════════════════════════════════════╣"
    echo "  ║                                                          ║"
    echo "  ║  Pilih mode setup:                                       ║"
    echo "  ║                                                          ║"
    echo "  ║   1) 🐳  Generate Dockerfile                             ║"
    echo "  ║   2) 📦  Clone repo & build image                        ║"
    echo "  ║   3) 🚀  Gunakan Docker image dari registry              ║"
    echo "  ║                                                          ║"
    echo "  ╚══════════════════════════════════════════════════════════╝"
    echo ""
}

select_prepare_mode() {
    local app_name="$1"
    local app_desc="$2"

    show_mode_menu "${app_name}" "${app_desc}"

    local choice
    while true; do
        read -rp "  Pilihan [1-3]: " choice </dev/tty
        case "${choice}" in
            1) PREPARE_MODE="dockerfile"; break ;;
            2) PREPARE_MODE="clone";      break ;;
            3) PREPARE_MODE="image";      break ;;
            *) echo -e "  ${RED}❌ Pilihan tidak valid. Masukkan 1, 2, atau 3.${NC}" ;;
        esac
    done

    echo ""
    case "${PREPARE_MODE}" in
        dockerfile) echo -e "  ${CYAN}▶ Mode: Generate Dockerfile${NC}" ;;
        clone)      echo -e "  ${CYAN}▶ Mode: Clone repo & build image${NC}" ;;
        image)      echo -e "  ${CYAN}▶ Mode: Gunakan Docker image${NC}" ;;
    esac
    echo ""
}

# ============================================
# Prepare Single App
# ============================================

prepare_app() {
    local target="$1"
    local no_deps="${2:-false}"

    # ── Cek apakah app baru (belum di repos.csv) ─────────────────────────────
    if ! app_exists_in_repos "$target"; then
        log_header "🚀 App Baru: ${target} (belum terdaftar di repos.csv)"
        echo ""
        echo "App '${target}' belum ada di repositori. Akan dilakukan scaffolding interaktif..."
        echo ""

        scaffold_interactive "$target"

        echo ""
        echo "┌─────────────────────────────────────────────────────────────┐"
        echo "│ ✅ Scaffolding selesai!                                    │"
        echo "│    Sekarang lanjut ke fase prepare...                      │"
        echo "└─────────────────────────────────────────────────────────────┘"

        if ! load_app_config "$target"; then
            log_error "Gagal load konfigurasi '${target}' setelah scaffold. Cek repos.csv."
            exit 1
        fi
    else
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
    fi

    # ── Info box app ──────────────────────────────────────────────────────────
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────┐"
    printf "  │  App    : %-47s│\n" "${APP_NAME}"
    printf "  │  Desc   : %-47s│\n" "${APP_DESC:0:47}"
    printf "  │  Repo   : %-47s│\n" "${REPO_URL:0:47}"
    printf "  │  Branch : %-47s│\n" "${BRANCH}"
    printf "  │  Target : %-47s│\n" "site/${APP_DIR}"
    echo "  └─────────────────────────────────────────────────────────┘"

    # ── Pilih mode interaktif ─────────────────────────────────────────────────
    local PREPARE_MODE=""
    select_prepare_mode "${APP_NAME}" "${APP_DESC}"

    # ── Jalankan mode yang dipilih ────────────────────────────────────────────
    case "${PREPARE_MODE}" in
        dockerfile)
            run_mode_dockerfile
            ;;
        clone)
            run_mode_clone "${no_deps}"
            ;;
        image)
            run_mode_image
            ;;
        *)
            log_error "Mode tidak dikenal: ${PREPARE_MODE}"
            exit 1
            ;;
    esac

    echo ""
    log_success "${APP_NAME} prepare selesai! (mode: ${PREPARE_MODE})"
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
    local any_new=false
    for app in "${apps[@]}"; do
        if ! app_exists_in_repos "$app"; then
            any_new=true
        fi
        prepare_app "$app" "$no_deps"
    done

    echo ""
    echo "┌─────────────────────────────────────────────────────────────┐"
    echo "│ ✅  Semua aplikasi siap digunakan!                          │"
    echo "└─────────────────────────────────────────────────────────────┘"
    echo ""

    # Show next steps hint
    echo "Langkah selanjutnya:"
    if [ -f "${PROJECT_DIR}/scripts/build.sh" ]; then
        echo "  • Build Docker images:  ./scripts/build.sh [app]"
    fi
    if ls "${PROJECT_DIR}"/env/.env.prod.* 1>/dev/null 2>&1; then
        echo "  • File production .env sudah dibuat di folder env/ (JANGAN di-commit!)"
    fi
    echo ""
}

main "$@"
