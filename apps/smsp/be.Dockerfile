# ============================================
# Production smsp Image for Docker Hub
# Optimized: Build once, use 3x (app/queue/scheduler)
# ============================================
FROM php:8.4-fpm-alpine AS base

ARG UID=1000
ARG GID=1000
ARG TZ=Asia/Jakarta
ARG APP_NAME="Smartpresence Deskripsi"

ENV TZ=${TZ} \
    APP_ENV=production \
    PHP_MEMORY_LIMIT=512M \
    PHP_OPCACHE_VALIDATE_TIMESTAMPS=0 \
    APP_NAME=${APP_NAME}

# Install system dependencies and PHP extensions
RUN set -eux; \
    apk add --no-cache \
        tzdata \
        bash \
        shadow \
        ca-certificates \
        unzip \
        curl \
        openssl \
        su-exec \
        mariadb-client \
        mariadb-connector-c \
        libpq \
        icu-libs \
        oniguruma \
        libzip \
        zlib \
        libpng \
        libjpeg-turbo \
        freetype \
        libxml2 \
    ; \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        linux-headers \
        icu-dev \
        oniguruma-dev \
        libzip-dev \
        zlib-dev \
        libpng-dev \
        libjpeg-turbo-dev \
        freetype-dev \
        libxml2-dev \
        postgresql-dev \
    ; \
    cp /usr/share/zoneinfo/${TZ} /etc/localtime; \
    echo "${TZ}" > /etc/timezone; \
    docker-php-ext-configure intl; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" \
        intl \
        mbstring \
        pdo \
        pdo_mysql \
        pdo_pgsql \
        pgsql \
        zip \
        gd \
        bcmath \
        exif \
        pcntl \
        sockets \
        opcache \
    ; \
    pecl install igbinary apcu; \
    docker-php-ext-enable igbinary apcu; \
    apk del --no-network .build-deps; \
    rm -rf \
        /var/cache/apk/* \
        /tmp/* \
        /usr/src/php* \
        /root/.pearrc

# Create non-root user
RUN set -eux; \
    addgroup -g "${GID}" www; \
    adduser -D -G www -u "${UID}" www; \
    sed -ri 's/^user = .*/user = www/' /usr/local/etc/php-fpm.d/www.conf; \
    sed -ri 's/^group = .*/group = www/' /usr/local/etc/php-fpm.d/www.conf; \
    sed -ri 's|^;?clear_env =.*|clear_env = no|' /usr/local/etc/php-fpm.d/www.conf

# ============================================
# Stage 2: Build & Dependencies
# ============================================
FROM base AS builder

ARG APP_DIR=

ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_CACHE_DIR=/tmp/composer-cache \
    COMPOSER_MEMORY_LIMIT=-1 \
    COMPOSER_NO_INTERACTION=1

WORKDIR /build

# Copy composer binary only in builder
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Copy only composer files first (better caching)
COPY sources/${APP_DIR}/composer.json sources/${APP_DIR}/composer.lock* ./

# Install composer dependencies with optimization
RUN set -eux; \
    composer install \
      --no-dev \
      --prefer-dist \
      --no-interaction \
      --no-progress \
      --no-scripts \
      --optimize-autoloader \
      --classmap-authoritative; \
    rm -rf "$COMPOSER_CACHE_DIR" /root/.composer /tmp/*

# Copy entire application code
COPY sources/${APP_DIR}/ ./

# Finalize: dump autoloader and optimize, clean up dev files
RUN set -eux; \
    rm -rf \
        .git \
        .github \
        node_modules \
        tests \
        storage/logs/* \
        storage/framework/cache/* \
        storage/framework/sessions/* \
        storage/framework/views/* \
        bootstrap/cache/*.php \
        .env \
        .env.* \
        npm-debug.log \
        yarn-error.log \
        pnpm-debug.log \
    ; \
    composer dump-autoload --optimize --classmap-authoritative --no-scripts 2>/dev/null || true; \
    # Clear any potential config caches created during composer commands
    if [ -f artisan ]; then \
      php artisan config:clear 2>/dev/null || true; \
    fi; \
    if [ -d vendor/livewire ]; then \
      echo "✅ Livewire verified"; \
    else \
      echo "⚠️ Livewire not found in dependencies"; \
    fi; \
    rm -rf "$COMPOSER_CACHE_DIR" /root/.composer /tmp/*

# ============================================
# Stage 3: Runtime (Final Image)
# ============================================
FROM base AS runtime

ARG TZ=Asia/Jakarta
ARG APP_NAME="Smartpresence Deskripsi"

ENV APP_ENV=production \
    APP_WORKDIR=/var/www/smsp/ \
    PHP_OPCACHE_VALIDATE_TIMESTAMPS=0 \
    PHP_MEMORY_LIMIT=512M \
    APP_NAME=${APP_NAME}

WORKDIR ${APP_WORKDIR}

# PHP Configuration (production optimized)
RUN set -eux; \
  { \
    echo "memory_limit=${PHP_MEMORY_LIMIT}"; \
    echo "upload_max_filesize=64M"; \
    echo "post_max_size=64M"; \
    echo "max_execution_time=120"; \
    echo "max_input_time=120"; \
    echo "max_input_vars=3000"; \
    echo "date.timezone=${TZ}"; \
    echo "expose_php=Off"; \
    echo "display_errors=Off"; \
    echo "log_errors=On"; \
    echo "error_log=/var/log/php_errors.log"; \
  } > /usr/local/etc/php/conf.d/laravel.ini; \
  { \
    echo "opcache.enable=1"; \
    echo "opcache.enable_cli=0"; \
    echo "opcache.jit=1255"; \
    echo "opcache.jit_buffer_size=128M"; \
    echo "opcache.memory_consumption=256"; \
    echo "opcache.interned_strings_buffer=32"; \
    echo "opcache.max_accelerated_files=100000"; \
    echo "opcache.revalidate_freq=0"; \
    echo "opcache.validate_timestamps=${PHP_OPCACHE_VALIDATE_TIMESTAMPS}"; \
    echo "opcache.save_comments=1"; \
    echo "opcache.enable_file_override=1"; \
  } > /usr/local/etc/php/conf.d/opcache.ini; \
  { \
    echo "apc.enabled=1"; \
    echo "apc.shm_size=128M"; \
    echo "apc.enable_cli=0"; \
    echo "apc.ttl=3600"; \
  } > /usr/local/etc/php/conf.d/apcu.ini; \
  sed -ri 's|^;?pm =.*|pm = dynamic|' /usr/local/etc/php-fpm.d/www.conf; \
  sed -ri 's|^;?pm\.max_children =.*|pm.max_children = 50|' /usr/local/etc/php-fpm.d/www.conf; \
  sed -ri 's|^;?pm\.start_servers =.*|pm.start_servers = 8|' /usr/local/etc/php-fpm.d/www.conf; \
  sed -ri 's|^;?pm\.min_spare_servers =.*|pm.min_spare_servers = 4|' /usr/local/etc/php-fpm.d/www.conf; \
  sed -ri 's|^;?pm\.max_spare_servers =.*|pm.max_spare_servers = 16|' /usr/local/etc/php-fpm.d/www.conf; \
  sed -ri 's|^;?pm\.max_requests =.*|pm.max_requests = 1000|' /usr/local/etc/php-fpm.d/www.conf; \
  sed -ri 's|^;?clear_env =.*|clear_env = no|' /usr/local/etc/php-fpm.d/www.conf

# Copy application from builder stage
COPY --from=builder --chown=www:www /build ${APP_WORKDIR}

# Setup Laravel directories and permissions
RUN set -eux; \
    mkdir -p storage/app storage/framework/cache storage/framework/sessions storage/framework/views storage/logs bootstrap/cache; \
    chown -R www:www storage bootstrap/cache; \
    chmod -R ug+rwX storage bootstrap/cache; \
    chmod -R 775 storage/framework/views; \
    if [ -d public ]; then chmod -R 755 public; fi

# Copy entrypoint script
COPY docker/php/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 9000

# Lightweight health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD php -r "exit(extension_loaded('opcache') ? 0 : 1);"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm", "-F"]
