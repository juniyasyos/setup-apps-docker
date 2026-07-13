# syntax=docker/dockerfile:1

# ============================================================
# Production SIIMUT Image - Optimized Size
# Build once, use for app / queue / scheduler
# ============================================================

ARG PHP_VERSION=8.4
ARG ALPINE_VERSION=3.21

# ============================================================
# Stage 1: Base Runtime
# ============================================================
FROM php:${PHP_VERSION}-fpm-alpine${ALPINE_VERSION} AS base

ARG UID=1000
ARG GID=1000
ARG TZ=Asia/Jakarta

ENV TZ=${TZ} \
    APP_ENV=production \
    PHP_MEMORY_LIMIT=512M \
    PHP_OPCACHE_VALIDATE_TIMESTAMPS=0

# ------------------------------------------------------------
# Runtime libs + temporary build deps
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# Non-root user
# ------------------------------------------------------------
RUN set -eux; \
    addgroup -g "${GID}" www; \
    adduser -D -G www -u "${UID}" www; \
    sed -ri 's/^user = .*/user = www/' /usr/local/etc/php-fpm.d/www.conf; \
    sed -ri 's/^group = .*/group = www/' /usr/local/etc/php-fpm.d/www.conf; \
    sed -ri 's|^;?clear_env =.*|clear_env = no|' /usr/local/etc/php-fpm.d/www.conf

# ------------------------------------------------------------
# PHP production config
# ------------------------------------------------------------
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
        echo "error_log=/proc/self/fd/2"; \
    } > /usr/local/etc/php/conf.d/laravel.ini; \
    { \
        echo "opcache.enable=1"; \
        echo "opcache.enable_cli=0"; \
        echo "opcache.jit=0"; \
        echo "opcache.memory_consumption=192"; \
        echo "opcache.interned_strings_buffer=16"; \
        echo "opcache.max_accelerated_files=50000"; \
        echo "opcache.revalidate_freq=0"; \
        echo "opcache.validate_timestamps=${PHP_OPCACHE_VALIDATE_TIMESTAMPS}"; \
        echo "opcache.save_comments=1"; \
    } > /usr/local/etc/php/conf.d/opcache.ini; \
    { \
        echo "apc.enabled=1"; \
        echo "apc.shm_size=64M"; \
        echo "apc.enable_cli=0"; \
        echo "apc.ttl=3600"; \
    } > /usr/local/etc/php/conf.d/apcu.ini; \
    sed -ri 's|^;?pm =.*|pm = dynamic|' /usr/local/etc/php-fpm.d/www.conf; \
    sed -ri 's|^;?pm\.max_children =.*|pm.max_children = 30|' /usr/local/etc/php-fpm.d/www.conf; \
    sed -ri 's|^;?pm\.start_servers =.*|pm.start_servers = 6|' /usr/local/etc/php-fpm.d/www.conf; \
    sed -ri 's|^;?pm\.min_spare_servers =.*|pm.min_spare_servers = 3|' /usr/local/etc/php-fpm.d/www.conf; \
    sed -ri 's|^;?pm\.max_spare_servers =.*|pm.max_spare_servers = 10|' /usr/local/etc/php-fpm.d/www.conf; \
    sed -ri 's|^;?pm\.max_requests =.*|pm.max_requests = 1000|' /usr/local/etc/php-fpm.d/www.conf

# ============================================================
# Stage 2: Composer Builder
# ============================================================
FROM base AS builder

ARG APP_DIR=siimut

ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_CACHE_DIR=/tmp/composer-cache \
    COMPOSER_MEMORY_LIMIT=-1 \
    COMPOSER_NO_INTERACTION=1

WORKDIR /build

# Composer hanya ada di builder, tidak ikut runtime
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Copy composer files first for cache
COPY sources/${APP_DIR}/composer.json sources/${APP_DIR}/composer.lock* ./

RUN set -eux; \
    composer install \
        --no-dev \
        --prefer-dist \
        --no-interaction \
        --no-progress \
        --no-scripts \
        --optimize-autoloader \
        --classmap-authoritative; \
    rm -rf \
        "$COMPOSER_CACHE_DIR" \
        /root/.composer \
        /tmp/*

# Copy app source
COPY sources/${APP_DIR}/ ./

# Clean unnecessary files from final app payload
RUN set -eux; \
    rm -rf \
        .git \
        .github \
        node_modules \
        tests \
        docs \
        storage/logs/* \
        storage/framework/cache/* \
        storage/framework/cache/data/* \
        storage/framework/sessions/* \
        storage/framework/views/* \
        storage/framework/testing/* \
        storage/app/private/* \
        storage/app/public/* \
        bootstrap/cache/*.php \
        .env \
        .env.* \
        npm-debug.log \
        yarn-debug.log \
        yarn-error.log \
        pnpm-debug.log \
        README.md \
        CHANGELOG.md \
    ; \
    composer dump-autoload \
        --no-dev \
        --optimize \
        --classmap-authoritative \
        --no-scripts; \
    if [ -f artisan ]; then \
        php artisan package:discover --ansi || true; \
        php artisan config:clear || true; \
        php artisan route:clear || true; \
        php artisan view:clear || true; \
        php artisan event:clear || true; \
    fi; \
    rm -rf \
        "$COMPOSER_CACHE_DIR" \
        /root/.composer \
        /tmp/*

# ============================================================
# Stage 3: Runtime
# ============================================================
FROM base AS runtime

ARG APP_NAME="SIIMUT Application"
ARG APP_WORKDIR=/var/www/siimut

ENV APP_NAME=${APP_NAME} \
    APP_WORKDIR=${APP_WORKDIR}

WORKDIR ${APP_WORKDIR}

COPY --from=builder --chown=www:www /build ${APP_WORKDIR}

COPY docker/php/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN set -eux; \
    chmod +x /usr/local/bin/entrypoint.sh; \
    mkdir -p \
        storage/app \
        storage/app/public \
        storage/framework/cache \
        storage/framework/cache/data \
        storage/framework/sessions \
        storage/framework/views \
        storage/framework/testing \
        storage/logs \
        bootstrap/cache; \
    chown -R www:www storage bootstrap/cache; \
    chmod -R ug+rwX storage bootstrap/cache; \
    if [ -d public ]; then chmod -R 755 public; fi

EXPOSE 9000

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD php -r "exit(extension_loaded('opcache') && extension_loaded('pdo_mysql') ? 0 : 1);"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm", "-F"]