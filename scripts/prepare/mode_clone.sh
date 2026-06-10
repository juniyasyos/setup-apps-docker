#!/usr/bin/env bash
# =============================================================================
# prepare/mode_clone.sh — Mode 2: Clone Repo & Build Image
# =============================================================================
# Refactor dari existing phase_git / phase_env / phase_deps / phase_prod_env.
# Variabel yang diharapkan dari caller:
#   APP_NAME, APP_DIR, REPO_URL, BRANCH, HAS_PROD_ENV, HAS_LOCAL_DEPS
#   PROJECT_DIR, SCRIPT_DIR
# =============================================================================

# ──────────────────────────────────────────────
# Phase 1 — Git Clone / Pull
# ──────────────────────────────────────────────
phase_git() {
    log_header "📁 Git: ${APP_NAME}"

    local site_dir="${PROJECT_DIR}/sources/${APP_DIR}"

    mkdir -p "${PROJECT_DIR}/sources"

    if [ -d "${site_dir}/.git" ]; then
        echo ""
        echo -e "  ${YELLOW}⚠️  Repository sudah ada: sources/${APP_DIR}${NC}"
        echo ""
        echo "  Apa yang ingin dilakukan?"
        echo "  S) Skip  — abaikan, tidak pull"
        echo "  P) Pull  — git pull origin ${BRANCH}"
        echo "  R) Reset — hard reset + git pull (buang perubahan lokal)"
        echo ""

        local action
        while true; do
            read -rp "  Pilihan [P/s/r]: " action
            action="${action:-P}"
            case "${action^^}" in
                S)
                    echo -e "  ${BLUE}ℹ️  Git phase di-skip.${NC}"
                    return 0
                    ;;
                P)
                    echo "🔄 Pulling latest from branch '${BRANCH}'..."
                    cd "${site_dir}"
                    git fetch origin
                    if git rev-parse --verify "origin/${BRANCH}" > /dev/null 2>&1; then
                        git checkout "${BRANCH}" && git pull origin "${BRANCH}" \
                            && log_success "Git pull selesai." \
                            || { log_error "Git pull gagal!"; exit 1; }
                    else
                        echo "⚠️  Branch '${BRANCH}' tidak ada di origin, pull default..."
                        git pull origin || { log_error "Git pull gagal!"; exit 1; }
                    fi
                    cd "${SCRIPT_DIR}"
                    break
                    ;;
                R)
                    echo -e "  ${YELLOW}⚠️  Hard reset + pull...${NC}"
                    cd "${site_dir}"
                    git fetch origin
                    git checkout "${BRANCH}" 2>/dev/null || true
                    git reset --hard "origin/${BRANCH}" \
                        && log_success "Git reset + pull selesai." \
                        || { log_error "Git reset gagal!"; exit 1; }
                    cd "${SCRIPT_DIR}"
                    break
                    ;;
                *)
                    echo -e "  ${RED}❌ Pilihan tidak valid.${NC}" ;;
            esac
        done
    else
        echo "📥 Clone dari ${REPO_URL} (branch: ${BRANCH})..."
        if git clone -b "${BRANCH}" "${REPO_URL}" "${site_dir}" 2>/dev/null; then
            log_success "Git clone selesai."
        else
            echo "⚠️  Branch '${BRANCH}' tidak tersedia, clone default branch..."
            git clone "${REPO_URL}" "${site_dir}" \
                && log_success "Git clone selesai (default branch)." \
                || { log_error "Git clone gagal! Cek URL dan koneksi."; exit 1; }
        fi
    fi

    log_success "Git phase selesai untuk ${APP_NAME}"
}

# ──────────────────────────────────────────────
# Phase 2 — Setup .env
# ──────────────────────────────────────────────
phase_env() {
    local site_dir="${PROJECT_DIR}/sources/${APP_DIR}"

    log_header "📋 .env: ${APP_NAME}"

    # IAM pakai template berbeda
    if [ "${APP_NAME}" = "iam" ]; then
        echo "⏭️  IAM uses apps/iam as template; skipping .env copy"
        return 0
    fi

    if [ ! -f "${site_dir}/.env" ]; then
        if [ -f "${site_dir}/.env.example" ]; then
            echo "📋 Menyalin .env.example → .env..."
            cp "${site_dir}/.env.example" "${site_dir}/.env"
            log_success ".env berhasil dibuat."
        else
            log_warn ".env.example tidak ditemukan. Buat .env secara manual."
        fi
    else
        echo ""
        echo -e "  ${YELLOW}⚠️  .env sudah ada.${NC}"
        echo ""
        echo "  S) Skip  — biarkan .env yang ada"
        echo "  R) Reset — timpa dengan .env.example"
        echo ""
        local action
        while true; do
            read -rp "  Pilihan [S/r]: " action
            action="${action:-S}"
            case "${action^^}" in
                S) echo -e "  ${BLUE}ℹ️  .env dibiarkan.${NC}"; break ;;
                R)
                    if [ -f "${site_dir}/.env.example" ]; then
                        cp "${site_dir}/.env.example" "${site_dir}/.env"
                        log_success ".env berhasil di-reset dari .env.example."
                    else
                        log_warn ".env.example tidak ditemukan, skip reset."
                    fi
                    break
                    ;;
                *) echo -e "  ${RED}❌ Pilihan tidak valid.${NC}" ;;
            esac
        done
    fi
}

# ──────────────────────────────────────────────
# Phase 3 — Local Dependencies & Build
# ──────────────────────────────────────────────
phase_deps() {
    local no_deps="${1:-false}"

    log_header "🔧 Dependencies: ${APP_NAME}"

    if [ "${no_deps}" = "true" ]; then
        echo "⏭️  Skipping dependencies (--no-deps flag)"
        return 0
    fi

    if [ "${HAS_LOCAL_DEPS}" != "yes" ]; then
        echo "⏭️  App tidak memerlukan local dependencies"
        return 0
    fi

    local site_dir="${PROJECT_DIR}/sources/${APP_DIR}"
    cd "${site_dir}"

    # Cek tools
    local missing=0
    for cmd in php composer node npm; do
        if ! command -v "$cmd" &> /dev/null; then
            log_error "$cmd tidak ditemukan. Install terlebih dahulu."
            missing=1
        fi
    done
    [ "$missing" -eq 1 ] && { log_error "Ada tools yang kurang, abort."; exit 1; }
    log_success "Dependency tools OK"

    # Composer
    if [ -f "composer.json" ]; then
        echo "📦 Menjalankan composer install..."
        composer install --no-interaction --optimize-autoloader \
            && log_success "Composer install selesai." \
            || echo "⚠️  composer install gagal (dilanjutkan)"
    fi

    # npm
    if [ -f "package.json" ]; then
        echo "📦 Menjalankan npm install..."
        npm install
        echo "🔨 Building frontend assets..."
        npm run build
        log_success "Frontend build selesai."
    fi

    # Laravel cache
    if [ -f "artisan" ]; then
        echo "🔍 Laravel setup detected, running cache commands..."
        php artisan config:cache --quiet  || echo "⚠️  config:cache gagal"
        php artisan route:cache  --quiet  || echo "⚠️  route:cache gagal"
        php artisan view:cache   --quiet  || echo "⚠️  view:cache gagal"
        php artisan livewire:publish --assets --quiet || echo "⚠️  livewire:publish gagal"
        log_success "Laravel cache selesai."
    fi

    cd "${SCRIPT_DIR}"
    log_success "Dependencies phase selesai untuk ${APP_NAME}"
}

# ──────────────────────────────────────────────
# Phase 4 — Production .env Generation
# ──────────────────────────────────────────────

generate_app_key() {
    if command -v php &> /dev/null; then
        echo "base64:$(php -r 'echo base64_encode(random_bytes(32));')"
    else
        echo "base64:$(openssl rand -base64 32 | tr -d '\n')"
    fi
}

generate_db_password()  { openssl rand -base64 16 | tr -d '\n'; }
generate_jwt_secret()   { openssl rand -hex 32; }

generate_passport_keys() {
    local priv_temp pub_temp
    priv_temp=$(mktemp)
    pub_temp=$(mktemp)
    openssl genrsa -out "${priv_temp}" 2048 2>/dev/null
    openssl rsa -in "${priv_temp}" -pubout -out "${pub_temp}" 2>/dev/null
    PASSPORT_PRIVATE_KEY=$(sed 's/$/\\/' "${priv_temp}" | tr -d '\n' | sed 's/\\$//')
    PASSPORT_PUBLIC_KEY=$(sed  's/$/\\/' "${pub_temp}"  | tr -d '\n' | sed 's/\\$//')
    rm -f "${priv_temp}" "${pub_temp}"
}

phase_prod_env() {
    log_header "🔐 Production Env: ${APP_NAME}"

    if [ "${HAS_PROD_ENV}" != "yes" ]; then
        echo "⏭️  App tidak memerlukan production env generation"
        return 0
    fi

    local prod_env_file="${PROJECT_DIR}/env/.env.prod.${APP_NAME}"

    if [ -f "${prod_env_file}" ]; then
        echo ""
        echo -e "  ${YELLOW}⚠️  ${prod_env_file} sudah ada.${NC}"
        echo ""
        echo "  S) Skip  — gunakan file yang ada"
        echo "  R) Regenerate — generate ulang secrets"
        echo ""
        local action
        while true; do
            read -rp "  Pilihan [S/r]: " action
            action="${action:-S}"
            case "${action^^}" in
                S) echo -e "  ${BLUE}ℹ️  Production env dibiarkan.${NC}"; return 0 ;;
                R) echo -e "  ${YELLOW}⚠️  Regenerating secrets...${NC}"; break ;;
                *) echo -e "  ${RED}❌ Pilihan tidak valid.${NC}" ;;
            esac
        done
    fi

    if [ ! -f "${PROJECT_DIR}/apps/${APP_NAME}/.env.example" ]; then
        log_error "Template tidak ditemukan: apps/${APP_NAME}/.env.example"
        exit 1
    fi

    mkdir -p "${PROJECT_DIR}/env"
    echo "📋 Membuat production env dari template..."
    cp "${PROJECT_DIR}/apps/${APP_NAME}/.env.example" "${prod_env_file}"

    echo ""
    echo "🔧 Generating secrets..."

    APP_KEY=$(generate_app_key);             echo "  ✓ APP_KEY generated"
    DB_PASSWORD=$(generate_db_password);     echo "  ✓ DB_PASSWORD generated"
    MYSQL_ROOT_PASSWORD=$(generate_db_password); echo "  ✓ MYSQL_ROOT_PASSWORD generated"

    local temp_file="${prod_env_file}.tmp"
    cp "${prod_env_file}" "${temp_file}"

    sed -i "s|^APP_KEY=.*|APP_KEY=${APP_KEY}|"                         "${temp_file}"
    sed -i "s|^MYSQL_PASSWORD=.*|MYSQL_PASSWORD=${DB_PASSWORD}|"       "${temp_file}"
    sed -i "s|^MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}|" "${temp_file}"

    case "${APP_NAME}" in
        iam)
            IAM_JWT_SECRET=$(generate_jwt_secret)
            echo "  ✓ IAM_JWT_SECRET generated"
            sed -i "s|^IAM_JWT_SECRET=.*|IAM_JWT_SECRET=${IAM_JWT_SECRET}|" "${temp_file}"

            echo "  ⏳ Generating Passport RSA keys..."
            generate_passport_keys
            sed -i '/^PASSPORT_PRIVATE_KEY=/,/^-----END PRIVATE KEY-----/d' "${temp_file}"
            sed -i '/^PASSPORT_PUBLIC_KEY=/,/^-----END PUBLIC KEY-----/d'   "${temp_file}"
            { echo ""; echo "PASSPORT_PRIVATE_KEY=\"${PASSPORT_PRIVATE_KEY}\""; echo "PASSPORT_PUBLIC_KEY=\"${PASSPORT_PUBLIC_KEY}\""; } >> "${temp_file}"
            echo "  ✓ Passport RSA keys generated"
            ;;

        siimut)
            local iam_env="${PROJECT_DIR}/env/.env.prod.iam"
            if [ -f "${iam_env}" ]; then
                local jwt
                jwt=$(grep '^IAM_JWT_SECRET=' "${iam_env}" | cut -d '=' -f 2)
                if [ -n "$jwt" ]; then
                    IAM_JWT_SECRET="$jwt"
                    echo "  ✓ IAM_JWT_SECRET synced dari env/.env.prod.iam"
                else
                    IAM_JWT_SECRET=$(generate_jwt_secret)
                    echo "  ⚠️  Tidak bisa parse IAM_JWT_SECRET, generated baru"
                fi
            else
                IAM_JWT_SECRET=$(generate_jwt_secret)
                echo "  ⚠️  env/.env.prod.iam tidak ditemukan, generated baru"
            fi
            sed -i "s|^IAM_JWT_SECRET=.*|IAM_JWT_SECRET=${IAM_JWT_SECRET}|" "${temp_file}"
            ;;
    esac

    mv "${temp_file}" "${prod_env_file}"
    log_success "Secrets tersimpan di ${prod_env_file}"
    echo ""
    echo -e "  ${YELLOW}⚠️  PENTING: File ini ada di .gitignore — JANGAN di-commit!${NC}"
}

# ──────────────────────────────────────────────
# Main entry point untuk mode ini
# ──────────────────────────────────────────────
run_mode_clone() {
    local no_deps="${1:-false}"

    log_header "📦 Clone & Build: ${APP_NAME}"

    phase_git
    phase_env
    phase_deps "${no_deps}"
    phase_prod_env

    echo ""
    echo "  ┌─────────────────────────────────────────────────────────┐"
    echo "  │ ✅  Clone & setup selesai!                              │"
    echo "  │                                                         │"
    printf "  │  📁 sources/%-42s │\n" "${APP_DIR}"
    echo "  │                                                         │"
    echo "  │  Langkah selanjutnya:                                   │"
    echo "  │    ./rsch build ${APP_NAME}                             │"
    echo "  └─────────────────────────────────────────────────────────┘"
    echo ""
}
