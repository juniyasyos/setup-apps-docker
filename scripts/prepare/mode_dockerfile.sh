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
        read -rp "  Pilihan [1]: " choice
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
    local dest_dir="${PROJECT_DIR}/docker/${APP_NAME}"
    local dest_file="${dest_dir}/Dockerfile"
    local entrypoint_file="${dest_dir}/entrypoint.sh"

    # Handle existing file
    if [ -f "${dest_file}" ]; then
        echo ""
        echo -e "  ${YELLOW}⚠️  Dockerfile sudah ada: docker/${APP_NAME}/Dockerfile${NC}"
        echo ""
        echo "  Apa yang ingin dilakukan?"
        echo "  S) Skip — biarkan file yang ada"
        echo "  R) Replace — timpa dengan template baru"
        echo ""
        local action
        while true; do
            read -rp "  Pilihan [S/r]: " action
            action="${action:-S}"
            case "${action^^}" in
                S) echo -e "  ${BLUE}ℹ️  Dockerfile dibiarkan, skip generate.${NC}"; return 0 ;;
                R) echo -e "  ${YELLOW}⚠️  Menimpa Dockerfile yang ada...${NC}"; break ;;
                *) echo -e "  ${RED}❌ Pilihan tidak valid. Masukkan S atau R.${NC}" ;;
            esac
        done
    fi

    mkdir -p "${dest_dir}"
    log_info "Generating Dockerfile untuk ${APP_NAME} (Laravel) → docker/${APP_NAME}/Dockerfile"

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

COPY docker/${APP_NAME}/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 9000

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \\
  CMD php -r "exit(extension_loaded('opcache') && extension_loaded('apcu') ? 0 : 1);"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm", "-F"]
DOCKERFILE

    log_success "Dockerfile berhasil dibuat: docker/${APP_NAME}/Dockerfile"

    # ── Tulis entrypoint.sh jika belum ada ────────────────────────────────────
    if [ ! -f "${entrypoint_file}" ]; then
        log_info "Generating entrypoint.sh → docker/${APP_NAME}/entrypoint.sh"
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

# Warm up caches
echo "⚙️  Warming up caches..."
php artisan config:cache  >/dev/null 2>&1 || echo "⚠️ config:cache failed"
php artisan route:cache   >/dev/null 2>&1 || echo "⚠️ route:cache failed"
php artisan view:cache    >/dev/null 2>&1 || echo "⚠️ view:cache failed"
php artisan event:cache   >/dev/null 2>&1 || echo "⚠️ event:cache failed"

# Livewire assets
if [ ! -d "public/vendor/livewire" ]; then
    php artisan livewire:publish --assets || echo "⚠️ livewire:publish failed"
fi

# Fix permissions
[ -d storage ] && chown -R www:www storage bootstrap/cache 2>/dev/null || true
[ -d storage ] && chmod -R ug+rwX storage bootstrap/cache 2>/dev/null || true

echo "✅ Container ready at: $(date)"

[ $# -eq 0 ] && set -- php-fpm -F
echo "🚀 Starting: $*"
exec "$@"
ENTRYPOINT
        chmod +x "${entrypoint_file}"
        log_success "entrypoint.sh berhasil dibuat: docker/${APP_NAME}/entrypoint.sh"
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

    echo ""
    echo "  ┌─────────────────────────────────────────────────────────┐"
    echo "  │ ✅  Dockerfile siap!                                    │"
    echo "  │                                                         │"
    printf "  │  📄 docker/%-40s │\n" "${APP_NAME}/Dockerfile"
    printf "  │  🔧 docker/%-40s │\n" "${APP_NAME}/entrypoint.sh"
    echo "  │                                                         │"
    echo "  │  Langkah selanjutnya:                                   │"
    echo "  │    ./rsch build ${APP_NAME}                             │"
    echo "  └─────────────────────────────────────────────────────────┘"
    echo ""
}
