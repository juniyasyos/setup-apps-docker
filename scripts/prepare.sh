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
# For NEW apps (not in apps/<name>/app.yml):
#   ./prepare.sh <new-app>          # Interactive scaffolding then prepare
# =========================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ============================================
# Source libraries
# ============================================
SCAFFOLD_SCRIPT="${SCRIPT_DIR}/scaffold.sh"

source "${SCRIPT_DIR}/prepare/mode_dockerfile.sh"
source "${SCRIPT_DIR}/prepare/mode_clone.sh"
source "${SCRIPT_DIR}/prepare/mode_image.sh"

# ============================================
# Global Options
# ============================================
SKIP_EXISTING="false"
IS_ALL="false"

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

# App Configuration from app.yml (Single Source of Truth)
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
    APP_ROLES=(); APP_PAIRS=()

    local apps_dir="${PROJECT_DIR}/apps"
    if [ ! -d "$apps_dir" ]; then
        log_error "Apps directory not found: $apps_dir"
        exit 1
    fi

    for app_yml in "${apps_dir}"/*/app.yml; do
        [ -f "$app_yml" ] || continue
        
        local name dir repo branch has_prod has_deps desc
        name=$(grep -E "^name:" "$app_yml" | awk '{print $2}' | tr -d '\r"' || echo "")
        [ -z "$name" ] && continue

        dir=$(grep -E "^source_dir:" "$app_yml" | awk '{print $2}' | tr -d '\r"' || echo "$name")
        repo=$(grep -E "^repo:" "$app_yml" | awk '{print $2}' | tr -d '\r"' || echo "")
        branch=$(grep -E "^branch:" "$app_yml" | awk '{print $2}' | tr -d '\r"' || echo "main")
        
        has_prod=$(grep -E "^has_prod_env:" "$app_yml" | awk '{print $2}' | tr -d '\r"' | tr '[:upper:]' '[:lower:]' || echo "false")
        if [[ "$has_prod" == "true" || "$has_prod" == "yes" || "$has_prod" == "1" ]]; then has_prod="yes"; else has_prod="no"; fi

        has_deps=$(grep -E "^has_local_deps:" "$app_yml" | awk '{print $2}' | tr -d '\r"' | tr '[:upper:]' '[:lower:]' || echo "false")
        if [[ "$has_deps" == "true" || "$has_deps" == "yes" || "$has_deps" == "1" ]]; then has_deps="yes"; else has_deps="no"; fi

        desc=$(grep -E "^description:" "$app_yml" | sed 's/^description:[[:space:]]*//' | tr -d '\r"' || echo "$name")
        
        local role pair has_fe fe_name
        role=$(grep -E "^role:" "$app_yml" | awk '{print $2}' | tr -d '\r"' || echo "standalone")
        
        has_fe=$(grep -E "^has_frontend:" "$app_yml" | awk '{print $2}' | tr -d '\r"' | tr '[:upper:]' '[:lower:]' || echo "false")
        fe_name=$(grep -E "^fe_name:" "$app_yml" | awk '{print $2}' | tr -d '\r"' || echo "")
        
        if [[ "$has_fe" == "true" || "$has_fe" == "yes" || "$has_fe" == "1" ]] && [ -n "$fe_name" ]; then
            pair="$fe_name"
        else
            pair=""
        fi

        APP_NAMES+=("$name")
        APP_DIRS+=("$dir")
        APP_REPOS+=("$repo")
        APP_BRANCHES+=("$branch")
        APP_HAS_PROD+=("$has_prod")
        APP_HAS_DEPS+=("$has_deps")
        APP_DESCS+=("$desc")
        APP_ROLES+=("$role")
        APP_PAIRS+=("$pair")

        if [[ "$has_fe" == "true" || "$has_fe" == "yes" || "$has_fe" == "1" ]] && [ -n "$fe_name" ]; then
            local fe_dir fe_repo fe_branch fe_has_prod fe_has_deps fe_desc
            fe_dir=$(grep -E "^fe_source_dir:" "$app_yml" | awk '{print $2}' | tr -d '\r"' || echo "$fe_name")
            fe_repo=$(grep -E "^fe_repo:" "$app_yml" | awk '{print $2}' | tr -d '\r"' || echo "")
            fe_branch=$(grep -E "^fe_branch:" "$app_yml" | awk '{print $2}' | tr -d '\r"' || echo "main")
            
            fe_has_prod=$(grep -E "^fe_has_prod_env:" "$app_yml" | awk '{print $2}' | tr -d '\r"' | tr '[:upper:]' '[:lower:]' || echo "false")
            if [[ "$fe_has_prod" == "true" || "$fe_has_prod" == "yes" || "$fe_has_prod" == "1" ]]; then fe_has_prod="yes"; else fe_has_prod="no"; fi
            
            fe_has_deps=$(grep -E "^fe_has_local_deps:" "$app_yml" | awk '{print $2}' | tr -d '\r"' | tr '[:upper:]' '[:lower:]' || echo "false")
            if [[ "$fe_has_deps" == "true" || "$fe_has_deps" == "yes" || "$fe_has_deps" == "1" ]]; then fe_has_deps="yes"; else fe_has_deps="no"; fi
            
            fe_desc=$(grep -E "^fe_description:" "$app_yml" | sed 's/^fe_description:[[:space:]]*//' | tr -d '\r"' || echo "$fe_name")
            
            APP_NAMES+=("$fe_name")
            APP_DIRS+=("$fe_dir")
            APP_REPOS+=("$fe_repo")
            APP_BRANCHES+=("$fe_branch")
            APP_HAS_PROD+=("$fe_has_prod")
            APP_HAS_DEPS+=("$fe_has_deps")
            APP_DESCS+=("$fe_desc")
            APP_ROLES+=("frontend")
            APP_PAIRS+=("$name")
        fi
    done
}

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

get_app_status() {
    local name="$1"
    local dir="$2"

    local c_cloned="No  "
    local c_dockerfile="Miss"
    local c_nginx="Miss"
    local c_env="Miss"
    local c_compose="Miss"
    local c_db="Off  "

    # Check command-v docker
    local has_docker=false
    if command -v docker &>/dev/null; then
        has_docker=true
    fi

    # 1. Cloned
    if [ -d "${PROJECT_DIR}/sources/${dir}" ]; then
        c_cloned="Yes "
    fi

    # 2. Dockerfile — priority: apps/${name}/be.Dockerfile > apps/${name}/Dockerfile > docker/${name}/Dockerfile > sources/${dir}/Dockerfile
    if [ -f "${PROJECT_DIR}/apps/${name}/be.Dockerfile" ]; then
        c_dockerfile="OK  "
    elif [ -f "${PROJECT_DIR}/apps/${name}/Dockerfile" ]; then
        c_dockerfile="OK  "
    elif [ -f "${PROJECT_DIR}/docker/${name}/Dockerfile" ] || [ -f "${PROJECT_DIR}/sources/${dir}/Dockerfile" ]; then
        c_dockerfile="OK  "
    fi

    # 3. Nginx config
    if [ -f "${PROJECT_DIR}/docker/nginx/conf.d/${name}.conf" ] || [ -f "${PROJECT_DIR}/docker/nginx/conf.d/${dir}.conf" ]; then
        c_nginx="OK  "
    fi

    # 4. Env file
    if [ -f "${PROJECT_DIR}/sources/${dir}/.env" ]; then
        c_env="OK  "
    fi

    # 5. Compose file
    if [ -f "${PROJECT_DIR}/compose/apps/${name}.yml" ] || [ -f "${PROJECT_DIR}/compose/apps/${dir}.yml" ]; then
        c_compose="OK  "
    fi

    # 6. DB Check
    local db_name=""
    if [ -f "${PROJECT_DIR}/apps/${name}/app.yml" ]; then
        db_name=$(grep -E "^database:" "${PROJECT_DIR}/apps/${name}/app.yml" | awk '{print $2}' | tr -d '\r' || echo "")
    fi
    [ -z "$db_name" ] && db_name="${name}_db" # fallback

    if [ "$has_docker" = true ]; then
        if docker ps --filter "name=database-service" --filter "status=running" --format "{{.Names}}" | grep -q "database-service"; then
            # database is running, check if database exists inside MySQL
            if docker exec database-service mysql -uroot -prootpass123 -e "SHOW DATABASES LIKE '${db_name}';" --silent 2>/dev/null | grep -q "${db_name}"; then
                c_db="Ready"
            else
                # Database is missing but service is running. Execute the init script directly to create it on-the-fly
                local init_sql="${PROJECT_DIR}/docker/db/sql/00-init-multi-db.sql"
                if [ -f "$init_sql" ]; then
                    docker exec -i database-service mysql -uroot -prootpass123 < "$init_sql" &>/dev/null || true
                    # Recheck database
                    if docker exec database-service mysql -uroot -prootpass123 -e "SHOW DATABASES LIKE '${db_name}';" --silent 2>/dev/null | grep -q "${db_name}"; then
                        c_db="Ready"
                    else
                        c_db="Miss "
                    fi
                else
                    c_db="Miss "
                fi
            fi
        fi
    fi

    # Colorize to match visual length
    local f_cloned=""
    if [ "$c_cloned" = "Yes " ]; then
        f_cloned="  ${GREEN}Yes${NC} "
    else
        f_cloned="  ${RED}No${NC}  "
    fi

    local f_dockerfile=""
    if [ "$c_dockerfile" = "OK  " ]; then
        f_dockerfile="    ${GREEN}OK${NC}    "
    else
        f_dockerfile="   ${RED}Miss${NC}   "
    fi

    local f_nginx=""
    if [ "$c_nginx" = "OK  " ]; then
        f_nginx="  ${GREEN}OK${NC}  "
    else
        f_nginx=" ${RED}Miss${NC} "
    fi

    local f_env=""
    if [ "$c_env" = "OK  " ]; then
        f_env="  ${GREEN}OK${NC}  "
    else
        f_env=" ${RED}Miss${NC} "
    fi

    local f_compose=""
    if [ "$c_compose" = "OK  " ]; then
        f_compose="  ${GREEN}OK${NC}   "
    else
        f_compose="  ${RED}Miss${NC} "
    fi

    local f_db=""
    if [ "$c_db" = "Ready" ]; then
        f_db="   ${GREEN}Ready${NC}    "
    elif [ "$c_db" = "Miss " ]; then
        f_db="    ${RED}Miss${NC}    "
    else
        f_db="  ${YELLOW}Offline${NC}   "
    fi

    echo "$f_cloned|$f_dockerfile|$f_nginx|$f_env|$f_compose|$f_db"
}

show_app_detail() {
    local target="$1"
    if ! load_app_config "$target"; then
        log_error "App '${target}' tidak dikenal!"
        exit 1
    fi

    local database=""
    local db_user=""
    local db_password=""
    local port=""
    local domain=""
    local php_version=""
    local queue=""
    local scheduler=""
    local version=""
    
    local yml_file="${PROJECT_DIR}/apps/${target}/app.yml"
    if [ -f "$yml_file" ]; then
        database=$(grep -E "^database:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
        db_user=$(grep -E "^db_user:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
        db_password=$(grep -E "^db_password:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
        port=$(grep -E "^port:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
        domain=$(grep -E "^domain:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
        php_version=$(grep -E "^php_version:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
        queue=$(grep -E "^queue:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
        scheduler=$(grep -E "^scheduler:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
        version=$(grep -E "^version:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
    fi

    # Fallback/defaults
    [ -z "$database" ] && database="${target}_db"
    [ -z "$db_user" ] && db_user="${target}_user"
    [ -z "$port" ] && port="N/A"
    [ -z "$domain" ] && domain="${target}.local"
    [ -z "$php_version" ] && php_version="N/A"
    [ -z "$queue" ] && queue="false"
    [ -z "$scheduler" ] && scheduler="false"
    [ -z "$version" ] && version="latest"

    # Status check of files
    local df_status="Missing"
    local df_path="apps/${target}/Dockerfile"
    if [ -f "${PROJECT_DIR}/apps/${target}/be.Dockerfile" ]; then
        df_status="Ready"
        df_path="apps/${target}/be.Dockerfile"
    elif [ -f "${PROJECT_DIR}/apps/${target}/Dockerfile" ]; then
        df_status="Ready"
    elif [ -f "${PROJECT_DIR}/docker/${target}/Dockerfile" ]; then
        df_status="Ready"
        df_path="docker/${target}/Dockerfile"
    elif [ -f "${PROJECT_DIR}/sources/${APP_DIR}/Dockerfile" ]; then
        df_status="Ready"
        df_path="sources/${APP_DIR}/Dockerfile"
    fi

    local nginx_status="Missing"
    local nginx_path="docker/nginx/conf.d/${target}.conf"
    if [ -f "${PROJECT_DIR}/docker/nginx/conf.d/${target}.conf" ]; then
        nginx_status="Ready"
    elif [ -f "${PROJECT_DIR}/docker/nginx/conf.d/${APP_DIR}.conf" ]; then
        nginx_status="Ready"
        nginx_path="docker/nginx/conf.d/${APP_DIR}.conf"
    fi

    local env_status="Missing"
    local env_path="sources/${APP_DIR}/.env"
    if [ -f "${PROJECT_DIR}/${env_path}" ]; then
        env_status="Ready"
    fi

    local compose_status="Missing"
    local compose_path="compose/apps/${target}.yml"
    if [ -f "${PROJECT_DIR}/${compose_path}" ]; then
        compose_status="Ready"
    elif [ -f "${PROJECT_DIR}/compose/apps/${APP_DIR}.yml" ]; then
        compose_status="Ready"
        compose_path="compose/apps/${APP_DIR}.yml"
    fi

    local db_status="Offline"
    if command -v docker &>/dev/null; then
        if docker ps --filter "name=database-service" --filter "status=running" --format "{{.Names}}" | grep -q "database-service"; then
            if docker exec database-service mysql -uroot -prootpass123 -e "SHOW DATABASES LIKE '${database}';" --silent 2>/dev/null | grep -q "${database}"; then
                db_status="Ready"
            else
                # Database is missing, auto-create using init script
                local init_sql="${PROJECT_DIR}/docker/db/sql/00-init-multi-db.sql"
                if [ -f "$init_sql" ]; then
                    docker exec -i database-service mysql -uroot -prootpass123 < "$init_sql" &>/dev/null || true
                    if docker exec database-service mysql -uroot -prootpass123 -e "SHOW DATABASES LIKE '${database}';" --silent 2>/dev/null | grep -q "${database}"; then
                        db_status="Ready"
                    else
                        db_status="Missing"
                    fi
                else
                    db_status="Missing"
                fi
            fi
        fi
    fi

    echo -e "\n${CYAN}══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${BLUE}📄 DETAIL APLIKASI: ${NC}${YELLOW}${APP_NAME}${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${CYAN}Nama App${NC}     : ${APP_NAME} (${target})"
    echo -e "  ${CYAN}Deskripsi${NC}    : ${APP_DESC}"
    echo -e "  ${CYAN}Git Repo${NC}     : ${REPO_URL}"
    echo -e "  ${CYAN}Cabang / Branch${NC}: ${BRANCH}"
    echo -e "  ${CYAN}Versi App${NC}    : ${version}"
    echo -e "  ${CYAN}PHP Version${NC}  : ${php_version}"
    echo -e "  ${CYAN}Local Deps${NC}   : $([ "${HAS_LOCAL_DEPS}" = "yes" ] && echo -e "${GREEN}✓ Ya${NC}" || echo -e "${RED}✗ Tidak${NC}")"
    echo -e "  ${CYAN}Queue Worker${NC} : $([ "${queue}" = "true" ] && echo -e "${GREEN}✓ Enabled${NC}" || echo -e "${RED}✗ Disabled${NC}")"
    echo -e "  ${CYAN}Scheduler${NC}    : $([ "${scheduler}" = "true" ] && echo -e "${GREEN}✓ Enabled${NC}" || echo -e "${RED}✗ Disabled${NC}")"
    echo ""
    echo -e "  ${BLUE}🌐 Network & Port:${NC}"
    echo -e "    • Local Domain : http://${domain}:${port}"
    echo -e "    • Internal Port: ${port}"
    echo ""
    echo -e "  ${BLUE}📁 Path & Konfigurasi:${NC}"
    echo -e "    • Source Code  : sources/${APP_DIR}  $([ -d "${PROJECT_DIR}/sources/${APP_DIR}" ] && echo -e "(${GREEN}Cloned${NC})" || echo -e "(${RED}Not Cloned${NC})")"
    echo -e "    • Dockerfile   : ${df_path}  $([ "${df_status}" = "Ready" ] && echo -e "(${GREEN}✓ Ada${NC})" || echo -e "(${RED}✗ Belum ada${NC})")"
    echo -e "    • Nginx Config : ${nginx_path}  $([ "${nginx_status}" = "Ready" ] && echo -e "(${GREEN}✓ Ada${NC})" || echo -e "(${RED}✗ Belum ada${NC})")"
    echo -e "    • Compose File : ${compose_path}  $([ "${compose_status}" = "Ready" ] && echo -e "(${GREEN}✓ Ada${NC})" || echo -e "(${RED}✗ Belum ada${NC})")"
    echo -e "    • Environment  : ${env_path}  $([ "${env_status}" = "Ready" ] && echo -e "(${GREEN}✓ Configured${NC})" || echo -e "(${RED}✗ Not Configured${NC})")"
    echo ""
    echo -e "  ${BLUE}🗄️  Database Info:${NC}"
    echo -e "    • DB Name      : ${database}"
    echo -e "    • DB User      : ${db_user}"
    echo -e "    • DB Status    : $([ "${db_status}" = "Ready" ] && echo -e "${GREEN}✓ Ready${NC}" || { [ "${db_status}" = "Missing" ] && echo -e "${RED}✗ Database Belum Ada${NC}"; } || echo -e "${YELLOW}🔌 Database Service Offline${NC}")"
    echo ""
    echo -e "  ${BLUE}⚙️  Perintah CLI Detail untuk ${target}:${NC}"
    echo -e "    • Prepare app  : ${YELLOW}./rsch prepare ${target}${NC}"
    echo -e "    • Build image  : ${YELLOW}./rsch build ${target}${NC}"
    echo -e "    • Restart app  : ${YELLOW}./rsch restart ${target}${NC}"
    echo -e "    • Tail logs    : ${YELLOW}./rsch logs ${target}${NC}"
    echo -e "    • Health check : ${YELLOW}./rsch health ${target}${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════════${NC}\n"
}

list_apps() {
    load_all_apps

    echo ""
    echo "╔════════╤════════════╤═══════════════════╤════════╤════════════╤════════╤════════╤═════════╤═══════════════╗"
    echo "║                                      📦  Application Setup Status                                         ║"
    echo "╠════════╤════════════╤═══════════════════╤════════╤════════════╤════════╤════════╤═════════╤═══════════════╣"
    echo "║ App    │ Folder     │ Role              │ Cloned │ Dockerfile │ Nginx  │ Env    │ Compose │ DB Status     ║"
    echo "║────────┼────────────┼───────────────────┼────────┼────────────┼────────┼────────┼─────────┼───────────────║"

    for i in "${!APP_NAMES[@]}"; do
        local name="${APP_NAMES[$i]}"
        local folder="${APP_DIRS[$i]}"
        
        # Get checks
        local checks
        checks=$(get_app_status "$name" "$folder")
        
        IFS='|' read -r f_cloned f_dockerfile f_nginx f_env f_compose f_db <<< "$checks"
        
        local role="${APP_ROLES[$i]}"
        local pair="${APP_PAIRS[$i]}"
        local role_display="Standalone"
        if [ "$role" = "backend" ] && [ -n "$pair" ]; then
            role_display="BE (→${pair})"
        elif [ "$role" = "frontend" ] && [ -n "$pair" ]; then
            role_display="FE (of ${pair})"
        fi
        
        printf "║ %-6s │ %-10s │ %-17s │ %b │ %b │ %b │ %b │ %b │ %b ║\n" \
            "$name" "$folder" "$role_display" "$f_cloned" "$f_dockerfile" "$f_nginx" "$f_env" "$f_compose" "$f_db"
    done

    echo "╚════════╧════════════╧═══════════════════╧════════╧════════════╧════════╧════════╧═════════╧═══════════════╝"
    echo ""
    echo "── Cara Pakai ─────────────────────────────────────────────────────"
    echo "  ./prepare.sh                    — tampilkan status/daftar ini"
    echo "  ./prepare.sh list               — tampilkan status/daftar ini"
    echo "  ./prepare.sh detail <app>       — tampilkan detail konfigurasi & perintah app"
    echo "  ./prepare.sh <app>              — prepare app"
    echo "  ./prepare.sh <app1> <app2>      — prepare beberapa app sekaligus"
    echo "  ./prepare.sh mynewapp           — scaffolding + prepare app baru"
    echo "  ./prepare.sh siimut --no-deps   — skip install dependencies"
    echo "  ./prepare.sh all --skip         — prepare semua app (mode clone) tanpa interaksi/prompt"
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
# Auto-generate infrastructure if missing
# ============================================

ensure_app_infrastructure() {
    local name="$APP_NAME"
    local source_dir="$APP_DIR"
    local desc="${APP_DESC:-${name}}"

    local role="${APP_ROLES[0]}" # Wait, we need to check if it's frontend
    # To properly check if it's frontend, we can check APP_ROLES array for current APP_NAME, or just check APP_PAIRS
    # But it's easier to use _has_frontend or similar. Actually, in prepare.sh load_all_apps populates APP_ROLES.
    local app_role="standalone"
    local app_pair=""
    for i in "${!APP_NAMES[@]}"; do
        if [ "${APP_NAMES[$i]}" = "$name" ]; then
            app_role="${APP_ROLES[$i]}"
            app_pair="${APP_PAIRS[$i]}"
            break
        fi
    done

    local apps_dir="${PROJECT_DIR}/apps/${name}"
    local env_name=".env.example"
    local df_name="Dockerfile"

    if [ "$app_role" = "frontend" ] && [ -n "$app_pair" ]; then
        apps_dir="${PROJECT_DIR}/apps/${app_pair}"
        env_name="fe.env.example"
        df_name="fe.Dockerfile"
        # We don't check app.yml for frontend because it's merged in backend
    fi

    # ── Cek file-file dasar ──
    local perlu_generate=false
    local langkah_tambah=""

    if [ "$app_role" != "frontend" ]; then
        [ ! -f "${apps_dir}/app.yml" ]      && { langkah_tambah="${langkah_tambah}  • apps/${name}/app.yml\n";      perlu_generate=true; }
    fi
    [ ! -f "${apps_dir}/${df_name}" ] && [ ! -f "${apps_dir}/be.Dockerfile" ] && { langkah_tambah="${langkah_tambah}  • apps/${name}/${df_name}\n";   perlu_generate=true; }
    [ ! -f "${apps_dir}/${env_name}" ] && { langkah_tambah="${langkah_tambah}  • apps/${name}/${env_name}\n"; perlu_generate=true; }
    [ ! -f "${PROJECT_DIR}/compose/apps/${name}.yml" ] && { langkah_tambah="${langkah_tambah}  • compose/apps/${name}.yml\n";                perlu_generate=true; }
    [ ! -f "${PROJECT_DIR}/docker/nginx/conf.d/${name}.conf" ] && { langkah_tambah="${langkah_tambah}  • docker/nginx/conf.d/${name}.conf\n"; perlu_generate=true; }

    if [ "$perlu_generate" = false ]; then
        return 0    # semua sudah ada
    fi

    echo ""
    log_warn "App '${name}' belum memiliki file infrastruktur lengkap."
    echo ""
    echo "  File yang akan dibuat:"
    echo -e "$langkah_tambah"
    echo ""
    echo "  G) Generate — buat file-file yang kurang"
    echo "  S) Skip — lewati, nanti urus manual"
    echo ""
    local action
    while true; do
        read -rp "  Pilihan [G/s]: " action </dev/tty
        action="${action:-G}"
        case "${action^^}" in
            G) break ;;
            S) echo -e "  ${BLUE}ℹ️  Skip generate infrastruktur.${NC}"; return 0 ;;
            *) echo -e "  ${RED}❌ Pilihan tidak valid.${NC}" ;;
        esac
    done

    # ── Generate missing files via scaffold.sh (subprocess to avoid function/var conflicts) ──
    local app_yml="${PROJECT_DIR}/apps/${name}/app.yml"
    if [ ! -f "$app_yml" ]; then
        log_info "Generating apps/${name}/app.yml..."
        mkdir -p "$(dirname "$app_yml")"
        
        # Check if scaffold.sh needs variables exported to render app.yml
        # Let's detect port
        local default_port
        if [ -f "${PROJECT_DIR}/scripts/scaffold.sh" ]; then
            default_port=$(bash -c "source ${PROJECT_DIR}/scripts/scaffold.sh && detect_next_port" 2>/dev/null || echo "8080")
        else
            default_port="8080"
        fi

        local prod_flag="no"
        local deps_flag="no"
        [ "$HAS_PROD_ENV" = "true" ] && prod_flag="yes"
        [ "$HAS_LOCAL_DEPS" = "true" ] && deps_flag="yes"

        export \
            APP_NAME="$name" \
            APP_DESC="${APP_DESC:-$name}" \
            APP_REPO="$REPO_URL" \
            APP_BRANCH="$BRANCH" \
            SOURCE_DIR="$source_dir" \
            IMAGE_NAME="$name" \
            IMAGE_VERSION="v1.0.0" \
            APP_PORT="$default_port" \
            APP_DOMAIN="${name}.local" \
            DB_NAME="${name}_db" \
            DB_USER="${name}_user" \
            DB_PASSWORD="${name}_password" \
            HAS_QUEUE="true" \
            HAS_SCHEDULER="true" \
            HAS_PROD_ENV="$prod_flag" \
            HAS_LOCAL_DEPS="$deps_flag" \
            PHP_VERSION="8.4"

        bash -c "source ${PROJECT_DIR}/scripts/scaffold.sh && render_template \"\${TEMPLATE_DIR}/app-yml.tpl\" \"$app_yml\""
        log_success "Created apps/${name}/app.yml"
    fi

    "${PROJECT_DIR}/scripts/scaffold.sh" render "$name"

    echo ""
    log_success "✅ Infrastruktur untuk ${name} sudah siap!"
}

# ============================================
# Prepare Single App
# ============================================

prepare_app() {
    local target="$1"
    local no_deps="${2:-false}"
    local _from_pair="${3:-false}"

    # ── Cek apakah app baru (belum ada app.yml) ─────────────────────────────
    if ! app_exists_in_repos "$target"; then
        log_header "🚀 App Baru: ${target} (belum terdaftar di apps/)"
        echo ""
        echo "App '${target}' belum ada di repositori. Akan dilakukan scaffolding interaktif..."
        echo ""

        "${SCAFFOLD_SCRIPT}" new "$target"

        echo ""
        echo "┌─────────────────────────────────────────────────────────────┐"
        echo "│ ✅ Scaffolding selesai!                                    │"
        echo "│    Sekarang lanjut ke fase prepare...                      │"
        echo "└─────────────────────────────────────────────────────────────┘"

        if ! load_app_config "$target"; then
            log_error "Gagal load konfigurasi '${target}' setelah scaffold. Cek app.yml."
            exit 1
        fi
    else
        # ── Cek fullstack project ──────────────────────────────────────────────
        local yml_file="${PROJECT_DIR}/apps/${target}/app.yml"
        if [ ! -f "$yml_file" ]; then
            # Maybe it's a frontend from a combined app.yml
            # We rely on load_app_config to populate APP_ROLES
            if ! load_app_config "$target"; then
                log_error "App '${target}' tidak dikenal!"
                exit 1
            fi
        else
            if ! load_app_config "$target"; then
                log_error "App '${target}' tidak dikenal!"
                exit 1
            fi
        fi
        
        # Now use APP_ROLES which is loaded correctly for both BE and FE
        local role="${APP_ROLES[0]}"
        local fullstack_pair="${APP_PAIRS[0]}"
        
        # If we target the frontend directly but we don't allow it, redirect.
        if [ "$role" = "frontend" ] && [ "$_from_pair" = "false" ] && [ -n "$fullstack_pair" ]; then
            if [ "${TARGET_BE}" = "true" ]; then
                log_warn "'${target}' adalah frontend dari project '${fullstack_pair}'"
                log_info "Redirecting ke project utama: ${fullstack_pair}"
                prepare_app "$fullstack_pair" "$no_deps" "false"
                return
            fi
        fi
    fi

    local skip_prepare=false
    local role="${APP_ROLES[0]}"
    local fullstack_pair="${APP_PAIRS[0]}"
    if [ "$role" = "frontend" ] && [ "${TARGET_FE}" = "false" ]; then skip_prepare=true; fi
    if [ "$role" = "backend" ] && [ "${TARGET_BE}" = "false" ]; then skip_prepare=true; fi

    if [ "$skip_prepare" = "false" ]; then
        # ── Info box app ──────────────────────────────────────────────────────────
        echo ""
        echo "  ┌─────────────────────────────────────────────────────────┐"
        printf "  │  App    : %-47s│\n" "${APP_NAME}"
        printf "  │  Desc   : %-47s│\n" "${APP_DESC:0:47}"
        printf "  │  Repo   : %-47s│\n" "${REPO_URL:0:47}"
        printf "  │  Branch : %-47s│\n" "${BRANCH}"
        printf "  │  Target : %-47s│\n" "sources/${APP_DIR}"
        echo "  └─────────────────────────────────────────────────────────┘"

        # ── Auto-generate infrastruktur yang kurang ────────────────────────────────
        ensure_app_infrastructure

        # ── Pilih mode interaktif ─────────────────────────────────────────────────
        local PREPARE_MODE=""
        if [ "${IS_ALL}" = "true" ]; then
            PREPARE_MODE="clone"
            echo -e "  ${CYAN}▶ Mode (Automated for ALL): Clone repo & build image${NC}"
            echo ""
        else
            select_prepare_mode "${APP_NAME}" "${APP_DESC}"
        fi

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
    fi

    # ── Di akhir prepare BE: otomatis prepare FE juga ─────────────────────
    if [ "$role" = "backend" ] && [ -n "$fullstack_pair" ] && [ "$_from_pair" = "false" ]; then
        if [ "${TARGET_FE}" = "true" ]; then
            echo ""
            log_header "🔗 Fullstack: Lanjut prepare frontend ${fullstack_pair}"
            prepare_app "$fullstack_pair" "$no_deps" "true"
        fi
    fi
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

    # "detail" → show specific app detail
    if [ "$1" = "detail" ]; then
        if [ -z "${2:-}" ]; then
            log_error "Usage: ./prepare.sh detail <app>"
            exit 1
        fi
        show_app_detail "$2"
        exit 0
    fi

    # Parse args: collect apps and flags
    local apps=()
    local no_deps=false
    TARGET_BE=true
    TARGET_FE=true

    for arg in "$@"; do
        case "$arg" in
            --no-deps|--no-dependencies)
                no_deps=true
                ;;
            --skip)
                SKIP_EXISTING="true"
                ;;
            --be)
                TARGET_FE=false
                ;;
            --fe)
                TARGET_BE=false
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
        IS_ALL="true"
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
