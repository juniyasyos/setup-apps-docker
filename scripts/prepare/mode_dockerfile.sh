#!/usr/bin/env bash
# =============================================================================
# prepare/mode_dockerfile.sh — Mode 1: Generate Dockerfile
# =============================================================================
# Dipanggil dari prepare.sh setelah user memilih mode "Generate Dockerfile".
# Variabel yang diharapkan sudah di-set oleh caller:
#   APP_NAME, APP_DIR, PROJECT_DIR
# =============================================================================

# ──────────────────────────────────────────────
# Sub-menu: Pilih Framework
# ──────────────────────────────────────────────
select_framework() {
    echo ""
    echo "  ┌─────────────────────────────────────┐"
    echo "  │   Pilih framework / stack:          │"
    echo "  │                                     │"
    echo "  │   1) 🐘  Laravel (PHP-FPM)          │"
    echo "  │   2) ⏳  Lainnya (coming soon...)   │"
    echo "  │                                     │"
    echo "  └─────────────────────────────────────┘"
    echo ""

    local choice
    while true; do
        read -rp "  Pilihan [1]: " choice </dev/tty
        choice="${choice:-1}"
        case "$choice" in
            1) FRAMEWORK="laravel"; break ;;
            2)
                echo ""
                echo -e "  ${YELLOW}⚠️  Framework lain belum tersedia, default ke Laravel.${NC}"
                FRAMEWORK="laravel"; break ;;
            *)
                echo -e "  ${RED}❌ Pilihan tidak valid. Masukkan 1.${NC}" ;;
        esac
    done
}

# ──────────────────────────────────────────────
# Generate Dockerfile untuk Laravel
# ──────────────────────────────────────────────
generate_laravel_dockerfile() {
    local dest_dir="${PROJECT_DIR}/apps/${APP_NAME}"
    local dest_file="${dest_dir}/Dockerfile"
    local entrypoint_file="${dest_dir}/entrypoint.sh"
    local template="${PROJECT_DIR}/docker/php/Dockerfile.template"

    # Handle existing file
    if [ -f "${dest_file}" ]; then
        echo ""
        echo -e "  ${YELLOW}⚠️  Dockerfile sudah ada: apps/${APP_NAME}/Dockerfile${NC}"
        echo ""
        echo "  Apa yang ingin dilakukan?"
        echo "  S) Skip — biarkan file yang ada"
        echo "  R) Replace — timpa dengan template baru"
        echo ""
        local action
        while true; do
            read -rp "  Pilihan [S/r]: " action </dev/tty
            action="${action:-S}"
            case "${action^^}" in
                S) echo -e "  ${BLUE}ℹ️  Dockerfile dibiarkan, skip generate.${NC}"; return 0 ;;
                R) echo -e "  ${YELLOW}⚠️  Menimpa Dockerfile yang ada...${NC}"; break ;;
                *) echo -e "  ${RED}❌ Pilihan tidak valid. Masukkan S atau R.${NC}" ;;
            esac
        done
    fi

    mkdir -p "${dest_dir}"
    log_info "Generating Dockerfile untuk ${APP_NAME} (Laravel) → apps/${APP_NAME}/Dockerfile"

    # ── Tulis Dockerfile dari template ────────────────────────────────────────
    if [ ! -f "$template" ]; then
        log_error "Template not found: ${template}"
        return 1
    fi

    cp "$template" "${dest_file}"

    # Replace placeholders
    sed -i "s|{{APP_NAME}}|${APP_NAME}|g" "${dest_file}"
    sed -i "s|{{APP_DIR}}|${APP_DIR}|g" "${dest_file}"
    sed -i "s|{{DESCRIPTION}}|${APP_NAME}|g" "${dest_file}"

    log_success "Dockerfile berhasil dibuat dari template: apps/${APP_NAME}/Dockerfile"

    # ── Tulis entrypoint.sh jika belum ada ────────────────────────────────────
    if [ ! -f "${entrypoint_file}" ]; then
        log_info "Generating entrypoint.sh → apps/${APP_NAME}/entrypoint.sh"
        cat > "${entrypoint_file}" << 'ENTRYPOINT'
#!/bin/sh
set -e

echo "🚀 Starting ${APP_NAME:-App} (env: ${APP_ENV:-production})"

APP_ENV="${APP_ENV:-production}"
APP_WORKDIR="${APP_WORKDIR:-/var/www/html}"

echo "📁 Using APP_WORKDIR=${APP_WORKDIR}"
cd "${APP_WORKDIR}"

if [ ! -f artisan ]; then
    echo "❌ Laravel artisan not found in ${APP_WORKDIR}"
    exit 1
fi

# .env check
if [ "$APP_ENV" = "production" ]; then
    [ ! -f ".env" ] && echo "❌ .env not found in production mode." && exit 1
else
    [ ! -f ".env" ] && [ -f ".env.example" ] && cp .env.example .env
fi

# Helper untuk menjalankan command sebagai www user
run_as_www() {
    if command -v su-exec >/dev/null 2>&1; then
        su-exec www "$@"
    elif [ "$(id -u)" = "0" ]; then
        su -s /bin/sh www -c "$(printf '%s ' "$@")"
    else
        "$@"
    fi
}

# Wait for DB
echo "⏳ Waiting for database..."
php -r '
$host  = getenv("DB_HOST") ?: "db";
$port  = getenv("DB_PORT") ?: 3306;
$start = time();
while (true) {
    $fp = @fsockopen($host, $port, $e, $s, 2);
    if ($fp) { fclose($fp); fwrite(STDOUT, "✅ DB ready\n"); break; }
    if (time() - $start > 60) { fwrite(STDERR, "❌ DB timeout\n"); exit(1); }
    fwrite(STDOUT, "… waiting {$host}:{$port}\n");
    sleep(2);
}
'

# Fix permissions BEFORE cache warming
echo "🔧 Setting up permissions..."
mkdir -p storage/framework/cache/data \
         storage/framework/sessions \
         storage/framework/views \
         storage/framework/testing \
         storage/logs \
         storage/app/public \
         bootstrap/cache
touch storage/logs/laravel.log

# Hapus stale cache files untuk mencegah error filemtime()
echo "🧹 Cleaning stale cache files..."
rm -rf storage/framework/views/* 2>/dev/null || true
rm -rf storage/framework/cache/data/* 2>/dev/null || true
rm -f bootstrap/cache/*.php 2>/dev/null || true

# Set ownership dan permission SEBELUM menjalankan artisan
chown -R www:www storage bootstrap/cache 2>/dev/null || true
chmod -R ug+rwX storage bootstrap/cache 2>/dev/null || true
chmod 664 storage/logs/laravel.log 2>/dev/null || true

echo "✅ Permissions set"

# Warm up caches — dijalankan sebagai www user untuk mencegah file ownership mismatch
echo "⚙️  Warming up caches..."
run_as_www php artisan config:cache  >/dev/null 2>&1 || echo "⚠️ config:cache failed"
# Skip route:cache untuk Livewire compatibility
echo "ℹ️ Skipping route:cache (Livewire compatibility)"
# Skip view:cache untuk mencegah error filemtime() pada storage volume
echo "ℹ️ Skipping view:cache (mencegah error filemtime pada runtime storage)"
run_as_www php artisan event:cache   >/dev/null 2>&1 || echo "⚠️ event:cache failed"

# Livewire assets (sebagai www user)
if [ ! -d "public/vendor/livewire" ]; then
    run_as_www php artisan livewire:publish --assets || echo "⚠️ livewire:publish failed"
fi

echo "✅ Container ready at: $(date)"

[ $# -eq 0 ] && set -- php-fpm -F
echo "🚀 Starting: $*"
exec "$@"
ENTRYPOINT
        chmod +x "${entrypoint_file}"
        log_success "entrypoint.sh berhasil dibuat: apps/${APP_NAME}/entrypoint.sh"
    else
        echo -e "  ${BLUE}ℹ️  entrypoint.sh sudah ada, dibiarkan.${NC}"
    fi
}

# ──────────────────────────────────────────────
# Main entry point untuk mode ini
# ──────────────────────────────────────────────
run_mode_dockerfile() {
    select_framework

    echo ""
    log_header "🐳 Generate Dockerfile: ${APP_NAME} (${FRAMEWORK})"

    case "${FRAMEWORK}" in
        laravel) generate_laravel_dockerfile ;;
        *)
            log_error "Framework '${FRAMEWORK}' belum didukung."
            return 1
            ;;
    esac

    # Cek dan buat konfigurasi Nginx, Compose, dan Database jika belum ada
    local database=""
    local db_user=""
    local db_password=""
    local port=""
    local domain=""
    local queue=""
    local scheduler=""
    local version=""
    local image=""

    local yml_file="${PROJECT_DIR}/apps/${APP_NAME}/app.yml"
    if [ -f "$yml_file" ]; then
        database=$(grep -E "^database:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
        db_user=$(grep -E "^db_user:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
        db_password=$(grep -E "^db_password:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
        port=$(grep -E "^port:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
        domain=$(grep -E "^domain:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
        queue=$(grep -E "^queue:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
        scheduler=$(grep -E "^scheduler:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
        version=$(grep -E "^version:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
        image=$(grep -E "^image:" "$yml_file" | awk '{print $2}' | tr -d '\r' || echo "")
    fi

    # Fallback/defaults
    [ -z "$database" ] && database="${APP_NAME}_db"
    [ -z "$db_user" ] && db_user="${APP_NAME}_user"
    [ -z "$db_password" ] && db_password="${APP_NAME}_pass123"
    [ -z "$port" ] && port="8080"
    [ -z "$domain" ] && domain="${APP_NAME}.local"
    [ -z "$queue" ] && queue="true"
    [ -z "$scheduler" ] && scheduler="true"
    [ -z "$version" ] && version="latest"
    [ -z "$image" ] && image="juniyasyos/${APP_NAME}"

    echo ""
    log_info "Memeriksa konfigurasi Nginx, Compose, dan Database..."

    # Source scaffold.sh functions if needed
    if ! declare -F gen_compose_app >/dev/null; then
        source "${PROJECT_DIR}/scripts/scaffold.sh"
    fi

    # 1. Nginx Config
    local nginx_path="${PROJECT_DIR}/docker/nginx/conf.d/${APP_NAME}.conf"
    if [ ! -f "$nginx_path" ]; then
        log_info "Generating Nginx Config → docker/nginx/conf.d/${APP_NAME}.conf"
        append_nginx_conf "$APP_NAME" "$APP_DIR" "$port" "${APP_DESC:-App}"
    else
        log_success "Nginx Config sudah ada."
    fi

    # 2. Compose File
    local compose_path="${PROJECT_DIR}/compose/apps/${APP_NAME}.yml"
    if [ ! -f "$compose_path" ]; then
        log_info "Generating Compose File → compose/apps/${APP_NAME}.yml"
        gen_compose_app "$APP_NAME" "$APP_DIR" "$image" "$version" "$port" \
            "$database" "$db_user" "$db_password" "${APP_DESC:-App}" \
            "$queue" "$scheduler"

        # Daftarkan ke compose files global
        py_insert_compose_yml "$APP_NAME" "$APP_DIR" "$queue" "$scheduler" "${APP_DESC:-App}" || true
        py_insert_web_yml "$APP_NAME" "$APP_DIR" "$port" || true
        py_insert_build_yml "$APP_NAME" "$APP_DIR" "$db_user" "$db_password" "$database" "${APP_DESC:-App}" || true
        append_env_files "$APP_NAME" "$port" || true
    else
        log_success "Compose File sudah ada."
    fi

    # 3. Database SQL Init Script
    local sql_init_file="${PROJECT_DIR}/docker/db/sql/00-init-multi-db.sql"
    if [ -f "$sql_init_file" ]; then
        if ! grep -q "CREATE DATABASE IF NOT EXISTS ${database}" "$sql_init_file"; then
            log_info "Appending Database SQL Init script → docker/db/sql/00-init-multi-db.sql"
            append_sql_init "$APP_NAME" "$database" "$db_user" "$db_password"
        else
            log_success "Database SQL Init script sudah terdaftar."
        fi
    else
        log_info "Generating Database SQL Init script → docker/db/sql/00-init-multi-db.sql"
        append_sql_init "$APP_NAME" "$database" "$db_user" "$db_password"
    fi

    echo ""
    echo "  ┌─────────────────────────────────────────────────────────┐"
    echo "  │ ✅  Dockerfile & Konfigurasi siap!                       │"
    echo "  │                                                         │"
    printf "  │  📄 docker/%-40s │\n" "${APP_NAME}/Dockerfile"
    printf "  │  🔧 docker/%-40s │\n" "${APP_NAME}/entrypoint.sh"
    printf "  │  🌐 nginx/%-41s │\n" "conf.d/${APP_NAME}.conf"
    printf "  │  🐳 compose/%-39s │\n" "apps/${APP_NAME}.yml"
    echo "  │                                                         │"
    echo "  │  Langkah selanjutnya:                                   │"
    echo "  │    ./rsch build ${APP_NAME}                             │"
    echo "  └─────────────────────────────────────────────────────────┘"
    echo ""
}
