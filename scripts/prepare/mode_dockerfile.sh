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
    echo "  │   2) ⚛️   Node.js (React/Vue/Vite)   │"
    echo "  │                                     │"
    echo "  └─────────────────────────────────────┘"
    echo ""

    local choice
    while true; do
        read -rp "  Pilihan [1]: " choice </dev/tty
        choice="${choice:-1}"
        case "$choice" in
            1) FRAMEWORK="laravel"; break ;;
            2) FRAMEWORK="react-vite"; break ;;
            *)
                echo -e "  ${RED}❌ Pilihan tidak valid. Masukkan 1 atau 2.${NC}" ;;
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
# Generate Dockerfile untuk Node.js (React/Vite)
# ──────────────────────────────────────────────
generate_react_dockerfile() {
    local dest_dir="${PROJECT_DIR}/apps/${APP_NAME}"
    local dest_file="${dest_dir}/Dockerfile"

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
    log_info "Generating Dockerfile untuk ${APP_NAME} (React/Vite) → apps/${APP_NAME}/Dockerfile"

    cat > "${dest_file}" << 'EOF'
# =============================================================================
# Dockerfile — {{APP_NAME}}
# Type       : Frontend Static App
# Framework  : React / Vite
# Build      : Node.js
# Runtime    : Nginx Alpine
# =============================================================================

# ─────────────────────────────────────────
# Stage 1: Build frontend
# ─────────────────────────────────────────
FROM node:24-alpine AS builder

ARG APP_NAME="{{APP_NAME}}"
ARG VITE_APP_NAME="{{APP_NAME}}"
ARG VITE_API_BASE_URL="/"

ENV VITE_APP_NAME=${VITE_APP_NAME}
ENV VITE_API_BASE_URL=${VITE_API_BASE_URL}

WORKDIR /app

COPY package*.json ./

RUN npm config set fetch-retries 5 && \
    npm config set fetch-retry-mintimeout 20000 && \
    npm config set fetch-retry-maxtimeout 120000 && \
    if [ -f package-lock.json ]; then npm ci; else npm install; fi

COPY . .

RUN npm run build


# ─────────────────────────────────────────
# Stage 2: Runtime Nginx
# ─────────────────────────────────────────
FROM nginx:1.27-alpine AS runtime

ARG APP_NAME="{{APP_NAME}}"

LABEL app.name="${APP_NAME}"
LABEL app.type="frontend-static"
LABEL app.framework="react-vite"

COPY --from=nginx_infra frontend-spa.conf /etc/nginx/conf.d/default.conf

COPY --from=builder /app/dist /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
  CMD wget -qO- http://127.0.0.1/health >/dev/null 2>&1 || exit 1

CMD ["nginx", "-g", "daemon off;"]
EOF

    # Replace placeholders
    sed -i "s|{{APP_NAME}}|${APP_NAME}|g" "${dest_file}"

    log_success "Dockerfile berhasil dibuat dari template: apps/${APP_NAME}/Dockerfile"
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
        react-vite) generate_react_dockerfile ;;
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

    # Generate missing Nginx, Compose, Database configs via scaffold.sh
    # Run as subprocess to avoid function/variable conflicts with prepare.sh
    "${PROJECT_DIR}/scripts/scaffold.sh" render "$APP_NAME"

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
