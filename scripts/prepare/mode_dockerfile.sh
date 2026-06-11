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

    # ── Tulis Dockerfile ──────────────────────────────────────────────────────
    cat > "${dest_file}" << DOCKERFILE
# =============================================================================
# Dockerfile — ${APP_NAME}
# Framework  : Laravel (PHP-FPM / Alpine)
# Generated  : $(date '+%Y-%m-%d %H:%M:%S')
# Generator  : rsch prepare (mode: dockerfile)
# =============================================================================

# ─────────────────────────────────────────
# Stage 1: Base — PHP + extensions
# ─────────────────────────────────────────
FROM php:8.4-fpm-alpine AS base

ARG UID=1000
ARG GID=1000
ARG TZ=Asia/Jakarta
ARG APP_NAME="${APP_NAME}"
ARG APP_WORKDIR=/var/www/html

RUN apk add --no-cache \\
      tzdata bash shadow ca-certificates unzip \\
      icu-dev oniguruma-dev libzip-dev zlib-dev \\
      libpng-dev libjpeg-turbo-dev freetype-dev \\
      libxml2-dev postgresql-dev \\
      linux-headers curl openssl \\
      \$PHPIZE_DEPS \\
      vim \\
  && cp /usr/share/zoneinfo/\${TZ} /etc/localtime \\
  && echo "\${TZ}" > /etc/timezone \\
  && docker-php-ext-configure intl \\
  && docker-php-ext-configure gd --with-freetype --with-jpeg \\
  && docker-php-ext-install -j"\$(nproc)" \\
       intl mbstring pdo pdo_mysql pdo_pgsql pgsql zip gd \\
       bcmath exif pcntl sockets opcache \\
  && pecl install apcu igbinary \\
  && docker-php-ext-enable apcu igbinary \\
  && apk del --no-network \$PHPIZE_DEPS linux-headers \\
  && rm -rf /var/cache/apk/* /tmp/*

# Composer dari image resmi
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# User non-root untuk runtime
RUN addgroup -g "\${GID}" www \\
  && adduser -D -G www -u "\${UID}" www \\
  && sed -ri 's/^user = .*/user = www/' /usr/local/etc/php-fpm.d/www.conf \\
  && sed -ri 's/^group = .*/group = www/' /usr/local/etc/php-fpm.d/www.conf

WORKDIR \${APP_WORKDIR}
ENV APP_NAME=\${APP_NAME}

# ─────────────────────────────────────────
# Stage 2: Dependencies — composer install
# ─────────────────────────────────────────
FROM base AS deps

ARG APP_DIR=${APP_DIR}
ENV COMPOSER_CACHE_DIR=/tmp/composer-cache \\
    COMPOSER_MEMORY_LIMIT=-1

WORKDIR \${APP_WORKDIR}

COPY . ./temp_context

RUN set -eux; \\
    echo ">> Building for APP_DIR='\${APP_DIR}'"; \\
    if [ -d "temp_context/site/\${APP_DIR}" ]; then \\
      cp -r "temp_context/site/\${APP_DIR}/." "./"; \\
    else \\
      cp -r "temp_context/." "./"; \\
    fi; \\
    rm -rf temp_context; \\
    if [ -f composer.json ]; then \\
      composer install \\
        --no-dev \\
        --prefer-dist \\
        --no-interaction \\
        --no-progress \\
        --optimize-autoloader \\
        --classmap-authoritative; \\
    fi; \\
    rm -rf "\$COMPOSER_CACHE_DIR" /tmp/*

# ─────────────────────────────────────────
# Stage 3: Runtime — Production
# ─────────────────────────────────────────
FROM base AS app

ARG TZ=Asia/Jakarta
ARG APP_NAME="${APP_NAME}"

ENV APP_ENV=production \\
    PHP_OPCACHE_VALIDATE_TIMESTAMPS=0 \\
    PHP_MEMORY_LIMIT=512M \\
    APP_NAME=\${APP_NAME}

# PHP & FPM production tuning
RUN set -eux; \\
  { \\
    echo "memory_limit=\${PHP_MEMORY_LIMIT}"; \\
    echo "upload_max_filesize=64M"; \\
    echo "post_max_size=64M"; \\
    echo "max_execution_time=120"; \\
    echo "max_input_time=120"; \\
    echo "max_input_vars=3000"; \\
    echo "date.timezone=\${TZ}"; \\
    echo "expose_php=Off"; \\
    echo "display_errors=Off"; \\
    echo "log_errors=On"; \\
    echo "error_log=/var/log/php_errors.log"; \\
  } > /usr/local/etc/php/conf.d/laravel.ini; \\
  { \\
    echo "opcache.enable=1"; \\
    echo "opcache.enable_cli=0"; \\
    echo "opcache.jit=1255"; \\
    echo "opcache.jit_buffer_size=128M"; \\
    echo "opcache.memory_consumption=256"; \\
    echo "opcache.interned_strings_buffer=32"; \\
    echo "opcache.max_accelerated_files=100000"; \\
    echo "opcache.revalidate_freq=0"; \\
    echo "opcache.validate_timestamps=\${PHP_OPCACHE_VALIDATE_TIMESTAMPS}"; \\
    echo "opcache.save_comments=1"; \\
    echo "opcache.enable_file_override=1"; \\
  } > /usr/local/etc/php/conf.d/opcache.ini; \\
  { \\
    echo "apc.enabled=1"; \\
    echo "apc.shm_size=128M"; \\
    echo "apc.enable_cli=0"; \\
    echo "apc.ttl=3600"; \\
  } > /usr/local/etc/php/conf.d/apcu.ini; \\
  sed -ri 's|^;?pm =.*|pm = dynamic|' /usr/local/etc/php-fpm.d/www.conf; \\
  sed -ri 's|^;?pm\\.max_children =.*|pm.max_children = 50|' /usr/local/etc/php-fpm.d/www.conf; \\
  sed -ri 's|^;?pm\\.start_servers =.*|pm.start_servers = 8|' /usr/local/etc/php-fpm.d/www.conf; \\
  sed -ri 's|^;?pm\\.min_spare_servers =.*|pm.min_spare_servers = 4|' /usr/local/etc/php-fpm.d/www.conf; \\
  sed -ri 's|^;?pm\\.max_spare_servers =.*|pm.max_spare_servers = 16|' /usr/local/etc/php-fpm.d/www.conf; \\
  sed -ri 's|^;?pm\\.max_requests =.*|pm.max_requests = 1000|' /usr/local/etc/php-fpm.d/www.conf; \\
  sed -ri 's|^;?request_terminate_timeout =.*|request_terminate_timeout = 120s|' /usr/local/etc/php-fpm.d/www.conf; \\
  sed -ri 's|^;?clear_env =.*|clear_env = no|' /usr/local/etc/php-fpm.d/www.conf; \\
  sed -ri 's|^;?access\\.log =.*|access.log = /proc/self/fd/2|' /usr/local/etc/php-fpm.d/www.conf

# Copy app + vendor dari stage deps
COPY --from=deps \${APP_WORKDIR} \${APP_WORKDIR}

# Permissions
RUN set -eux; \\
    if [ -d storage ]; then \\
      chown -R www:www storage bootstrap/cache || true; \\
      chmod -R ug+rwX storage bootstrap/cache || true; \\
    fi; \\
    if [ -d public ]; then \\
      chmod -R 755 public || true; \\
    fi

COPY apps/${APP_NAME}/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 9000

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \\
  CMD php -r "exit(extension_loaded('opcache') && extension_loaded('apcu') ? 0 : 1);"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm", "-F"]
DOCKERFILE

    log_success "Dockerfile berhasil dibuat: apps/${APP_NAME}/Dockerfile"

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
