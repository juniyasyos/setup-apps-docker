#!/usr/bin/env bash
# =============================================================================
# rsch scaffold — Library for generating new application files
# =============================================================================
# This script both serves as a standalone CLI and a library sourced by
# prepare.sh when scaffolding a new app interactively.
#
# Usage (standalone):
#   ./scripts/scaffold.sh <name>          # prompt for everything
#   ./scripts/scaffold.sh <name> --auto   # read apps/<name>/app.yml silently
#   ./scripts/scaffold.sh list            # list what can be scaffolded
#
# Sourced by prepare.sh (library mode):
#   source scripts/scaffold.sh
#   scaffold_interactive <name>
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ============================================
# Colors (redefine if not inherited)
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
# Utility — Python YAML insert helpers
# ============================================

# ============================================
# Python YAML manipulation scripts directory
# ============================================
PY_LIB="${SCRIPT_DIR}/.scaffold_py"
mkdir -p "$PY_LIB"

# Write a Python helper script for YAML manipulation
write_py_lib() {
    [ -f "${PY_LIB}/insert_compose.py" ] && return 0

    cat > "${PY_LIB}/insert_compose.py" << 'PYEOF'
import sys, os

filepath = os.environ['COMPOSE_YML']
name = os.environ['APP_NAME']
source_dir = os.environ['SOURCE_DIR']
desc = os.environ['APP_DESC']
has_queue = os.environ.get('HAS_QUEUE', 'true') == 'true'
has_scheduler = os.environ.get('HAS_SCHEDULER', 'true') == 'true'

with open(filepath, 'r') as f:
    content = f.read()

volumes_header = "# Named Volumes"
volumes_idx = content.find(volumes_header)
if volumes_idx == -1:
    print("ERROR: Cannot find Named Volumes section", file=sys.stderr)
    sys.exit(1)

svc_block = f"""
  # {desc}
  # Image: juniyasyos/{name}:VERSION
  app-{name}:
    extends:
      file: compose/apps/{name}.yml
      service: app
"""

if has_queue:
    svc_block += f"""
  queue-{name}:
    extends:
      file: compose/apps/{name}.yml
      service: queue
"""

if has_scheduler:
    svc_block += f"""
  scheduler-{name}:
    extends:
      file: compose/apps/{name}.yml
      service: scheduler
"""

insert_pos = content.rfind('\n', 0, volumes_idx - 1)
content = content[:insert_pos] + svc_block + content[insert_pos:]

vol_block = f"""
  # ── {name.upper()} ──────────────────────────────────────────
  {name}_public:
    driver: local
  {name}_storage:
    driver: local
  {name}_bootstrap_cache:
    driver: local
"""

networks_idx = content.find('\nnetworks:')
volumes_section_end = content.rfind('\n\n', 0, networks_idx)
content = content[:volumes_section_end] + vol_block + content[volumes_section_end:]

with open(filepath, 'w') as f:
    f.write(content)
print("OK")
PYEOF

    cat > "${PY_LIB}/insert_web.py" << 'PYEOF'
import sys, os

filepath = os.environ['WEB_YML']
name = os.environ['APP_NAME']
source_dir = os.environ['SOURCE_DIR']
port = os.environ['APP_PORT']
name_upper = name.upper()
host_port_var = f"{name_upper}_HOST_PORT"

with open(filepath, 'r') as f:
    content = f.read()

# Insert port entry into x-web-ports
ports_marker = "x-web-ports:"
ports_start = content.find(ports_marker)
if ports_start == -1:
    print("ERROR: Cannot find x-web-ports in web.yml", file=sys.stderr)
    sys.exit(1)

ports_end = content.find("\n\nx-", ports_start + 1)
if ports_end == -1:
    ports_end = content.find("\nservices:", ports_start + 1)

last_port_line = content.rfind('\n  - "', ports_start, ports_end)
if last_port_line == -1:
    last_port_line = ports_end

new_port = f'  - "${{{host_port_var}:{port}}}:{port}"\n'
content = content[:last_port_line] + '\n' + new_port + content[last_port_line + 1:]

# Insert volume entries into x-web-volumes
volumes_marker = "x-web-volumes:"
volumes_start = content.find(volumes_marker)
if volumes_start == -1:
    print("ERROR: Cannot find x-web-volumes", file=sys.stderr)
    sys.exit(1)

volumes_end = content.find("\n\nservices:", volumes_start + 1)

last_vol_line = content.rfind('\n  - ', volumes_start, volumes_end)
if last_vol_line == -1:
    last_vol_line = volumes_end

new_vols = f"  - {name}_public:/var/www/{source_dir}/public:ro\n  - {name}_storage:/var/www/{source_dir}/storage:ro\n"
content = content[:last_vol_line] + '\n' + new_vols + content[last_vol_line + 1:]

with open(filepath, 'w') as f:
    f.write(content)
print("OK")
PYEOF

    cat > "${PY_LIB}/insert_build.py" << 'PYEOF'
import sys, os

filepath = os.environ['BUILD_YML']
name = os.environ['APP_NAME']
source_dir = os.environ['SOURCE_DIR']
db_user = os.environ['DB_USER']
db_pass = os.environ['DB_PASSWORD']
database = os.environ['DB_NAME']
desc = os.environ['APP_DESC']

with open(filepath, 'r') as f:
    content = f.read()

content = content.rstrip()

build_block = f"""

  ####################################################################################################
  # {desc}
  ####################################################################################################
  {name}:
    build:
      context: .
      dockerfile: apps/{name}/Dockerfile
      args:
        UID: "1000"
        GID: "1000"
        TZ: "Asia/Jakarta"
        APP_NAME: "{desc}"
        APP_ENV: "production"
        APP_DIR: "{source_dir}"
        DB_HOST: "database-service"
        DB_USERNAME: "{db_user}"
        DB_PASSWORD: "{db_pass}"
        DB_DATABASE: "{database}"
        AWS_ACCESS_KEY_ID: "admin"
        AWS_SECRET_ACCESS_KEY: "password"
        AWS_BUCKET: "{name}"
        AWS_URL: "http://minio:9090/{name}"
        AWS_ENDPOINT: "http://minio:9090"
        BUILD_TIMESTAMP: "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    image: {name}:${{{name}_VERSION:-latest}}
    pull_policy: never
"""

content += build_block + '\n'

with open(filepath, 'w') as f:
    f.write(content)
print("OK")
PYEOF
}

# Insert a service block + volume block into compose.yml
py_insert_compose_yml() {
    local name="$1" source_dir="$2" has_queue="$3" has_scheduler="$4" desc="$5"

    write_py_lib
    APP_NAME="$name" SOURCE_DIR="$source_dir" HAS_QUEUE="$has_queue" \
        HAS_SCHEDULER="$has_scheduler" APP_DESC="$desc" \
        COMPOSE_YML="${PROJECT_DIR}/compose.yml" \
        python3 "${PY_LIB}/insert_compose.py"
}

# Insert port + volume into compose/base/web.yml
py_insert_web_yml() {
    local name="$1" source_dir="$2" port="$3"

    write_py_lib
    APP_NAME="$name" SOURCE_DIR="$source_dir" APP_PORT="$port" \
        WEB_YML="${PROJECT_DIR}/compose/base/web.yml" \
        python3 "${PY_LIB}/insert_web.py"
}

# Insert build service into compose/build.yml
py_insert_build_yml() {
    local name="$1" source_dir="$2" db_user="$3" db_pass="$4" database="$5" desc="$6"

    write_py_lib
    APP_NAME="$name" SOURCE_DIR="$source_dir" DB_USER="$db_user" \
        DB_PASSWORD="$db_pass" DB_NAME="$database" APP_DESC="$desc" \
        BUILD_YML="${PROJECT_DIR}/compose/build.yml" \
        python3 "${PY_LIB}/insert_build.py"
}

# ============================================
# Interactive prompt
# ============================================
scaffold_interactive() {
    local app_name="$1"

    log_header "🏗️  App Baru: ${app_name}"

    # ── Detect existing apps for defaults ──
    # Find highest port from repos.csv and web.yml
    local highest_port=8300
    if [ -f "${PROJECT_DIR}/compose/base/web.yml" ]; then
        # Extract all ports from x-web-ports
        local found_ports
        found_ports=$(grep -oP '\${\w+_HOST_PORT:-\K[0-9]+' "${PROJECT_DIR}/compose/base/web.yml}" 2>/dev/null || echo "")
        for p in $found_ports; do
            [ "$p" -gt "$highest_port" ] && highest_port="$p"
        done
    fi
    # Also check repos.csv port column (implied by name pattern)
    if [ -f "${PROJECT_DIR}/repos.csv" ]; then
        # Some ports might be defined only in env files
        for ef in "${PROJECT_DIR}/env/prod.env" "${PROJECT_DIR}/env/dev.env"; do
            if [ -f "$ef" ]; then
                local env_ports
                env_ports=$(grep -oP 'HOST_PORT=\K[0-9]+' "$ef" 2>/dev/null || echo "")
                for p in $env_ports; do
                    [ "$p" -gt "$highest_port" ] && highest_port="$p"
                done
            fi
        done
    fi
    local default_port=$((highest_port + 10))

    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║  Isi detail aplikasi baru                                    ║"
    echo "║  (tekan Enter untuk pakai nilai default di dalam kurung)     ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""

    # ── Prompt all fields with defaults ──
    read -r -p "  Nama app       [${app_name}]: " input_name
    NAME="${input_name:-$app_name}"

    read -r -p "  Deskripsi      [${NAME} - New Application]: " input_desc
    DESC="${input_desc:-${NAME} - New Application}"

    read -r -p "  Git repo URL   [https://github.com/juniyasyos/${NAME}.git]: " input_repo
    REPO="${input_repo:-https://github.com/juniyasyos/${NAME}.git}"

    read -r -p "  Branch         [main]: " input_branch
    BRANCH="${input_branch:-main}"

    read -r -p "  Source dir     [${NAME}]: " input_src_dir
    SOURCE_DIR="${input_src_dir:-$NAME}"

    read -r -p "  Image name     [juniyasyos/${NAME}]: " input_image
    IMAGE="${input_image:-juniyasyos/${NAME}}"

    read -r -p "  Version        [v1.0.0]: " input_ver
    VERSION="${input_ver:-v1.0.0}"

    read -r -p "  Port           [${default_port}]: " input_port
    PORT="${input_port:-$default_port}"

    read -r -p "  Domain         [${NAME}.local]: " input_domain
    DOMAIN="${input_domain:-${NAME}.local}"

    read -r -p "  Database name  [${NAME}_db]: " input_db
    DATABASE="${input_db:-${NAME}_db}"

    local default_db_user="${NAME}_user"
    read -r -p "  DB user        [${default_db_user}]: " input_db_user
    DB_USER="${input_db_user:-$default_db_user}"

    local default_db_pass="${NAME}-password"
    read -r -p "  DB password    [${default_db_pass}]: " input_db_pass
    DB_PASSWORD="${input_db_pass:-$default_db_pass}"

    read -r -p "  Queue worker?  [Y/n]: " input_queue
    HAS_QUEUE=true
    [[ "$input_queue" =~ ^[Nn] ]] && HAS_QUEUE=false

    read -r -p "  Scheduler?     [Y/n]: " input_scheduler
    HAS_SCHEDULER=true
    [[ "$input_scheduler" =~ ^[Nn] ]] && HAS_SCHEDULER=false

    read -r -p "  Prod env?      [Y/n]: " input_prod
    HAS_PROD_ENV=true
    [[ "$input_prod" =~ ^[Nn] ]] && HAS_PROD_ENV=false

    read -r -p "  Local deps?    [y/N]: " input_deps
    HAS_DEPS=false
    [[ "$input_deps" =~ ^[Yy] ]] && HAS_DEPS=true

    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║  Ringkasan                                                    ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"
    echo "║  App:        ${NAME}"
    echo "║  Desc:       ${DESC}"
    echo "║  Repo:       ${REPO}"
    echo "║  Branch:     ${BRANCH}"
    echo "║  Source:     ${SOURCE_DIR}"
    echo "║  Image:      ${IMAGE}:${VERSION}"
    echo "║  Port:       ${PORT}"
    echo "║  Database:   ${DATABASE} (user: ${DB_USER})"
    echo "║  Queue:      ${HAS_QUEUE}"
    echo "║  Scheduler:  ${HAS_SCHEDULER}"
    echo "║  Prod env:   ${HAS_PROD_ENV}"
    echo "║  Local deps: ${HAS_DEPS}"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""

    read -r -p "  Konfirmasi generate? [Y/n]: " confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        log_warn "Dibatalkan."
        exit 1
    fi

    # ── Store as app.yml for reference ──
    mkdir -p "${PROJECT_DIR}/apps/${NAME}"
    cat > "${PROJECT_DIR}/apps/${NAME}/app.yml" << APPYML
# ${DESC}
name: ${NAME}
repo: ${REPO}
branch: ${BRANCH}
source_dir: ${SOURCE_DIR}
image: ${IMAGE}
version: ${VERSION}
port: ${PORT}
domain: ${DOMAIN}
database: ${DATABASE}
db_user: ${DB_USER}
db_password: ${DB_PASSWORD}
queue: ${HAS_QUEUE}
scheduler: ${HAS_SCHEDULER}
php_version: "8.4"
has_prod_env: ${HAS_PROD_ENV}
has_local_deps: ${HAS_DEPS}
description: ${DESC}
APPYML
    log_success "Created apps/${NAME}/app.yml"

    # ── Generate all files ──
    scaffold_generate_all "$NAME" "$SOURCE_DIR" "$IMAGE" "$VERSION" "$PORT" \
        "$DATABASE" "$DB_USER" "$DB_PASSWORD" "$DESC" \
        "$HAS_QUEUE" "$HAS_SCHEDULER" "$REPO" "$BRANCH" "$HAS_PROD_ENV" "$HAS_DEPS"
}

# ============================================
# Generate all files for an app
# ============================================
scaffold_generate_all() {
    local name="$1" source_dir="$2" image="$3" version="$4" port="$5"
    local database="$6" db_user="$7" db_password="$8" desc="$9"
    local has_queue="${10}" has_scheduler="${11}" repo="${12}" branch="${13}"
    local has_prod_env="${14}" has_deps="${15}"

    log_header "📦 Generating files for ${name}..."

    gen_compose_app "$name" "$source_dir" "$image" "$version" "$port" \
        "$database" "$db_user" "$db_password" "$desc" \
        "$has_queue" "$has_scheduler"

    gen_dockerfile "$name" "$source_dir" "$desc"
    gen_env_example "$name" "$port" "$db_user" "$db_password" "$database"

    # Insert into YAML files (via Python)
    log_info "  Inserting into compose.yml..."
    py_insert_compose_yml "$name" "$source_dir" "$has_queue" "$has_scheduler" "$desc" || {
        log_error "Failed to update compose.yml"
        exit 1
    }
    log_success "  compose.yml updated"

    log_info "  Inserting into compose/base/web.yml..."
    py_insert_web_yml "$name" "$source_dir" "$port" || {
        log_error "Failed to update web.yml"
        exit 1
    }
    log_success "  compose/base/web.yml updated"

    log_info "  Inserting into compose/build.yml..."
    py_insert_build_yml "$name" "$source_dir" "$db_user" "$db_password" "$database" "$desc" || {
        log_error "Failed to update build.yml"
        exit 1
    }
    log_success "  compose/build.yml updated"

    # Append to flat files
    append_repos_csv "$name" "$source_dir" "$repo" "$branch" "$has_prod_env" "$has_deps" "$desc"
    append_nginx_conf "$name" "$source_dir" "$port" "$desc"
    append_sql_init "$name" "$database" "$db_user" "$db_password"
    append_env_files "$name" "$port"
    update_rsch_help "$name" "$port" "$desc"

    log_success "✅ Semua file untuk ${name} telah digenerate!"
}

# ============================================
# Generate compose/apps/<name>.yml
# ============================================
gen_compose_app() {
    local name="$1" source_dir="$2" image="$3" version="$4" port="$5"
    local database="$6" db_user="$7" db_pass="$8" desc="$9"
    local has_queue="${10}" has_scheduler="${11}"

    local target="${PROJECT_DIR}/compose/apps/${name}.yml"

    log_info "  compose/apps/${name}.yml"

    cat > "$target" << COMPEOF
# ${desc}
name: service-${name}

services:
  app:
    extends:
      file: ../base/php-base.yml
      service: php-app-base
    image: ${image}:${version}
    container_name: ${name}-app
    working_dir: /var/www/${source_dir}
    env_file:
      - ../../apps/${name}/.env.example
    environment:
      APP_ENV: production
      APP_DEBUG: "true"
      APP_WORKDIR: /var/www/${source_dir}
      PUBLIC_VOLUME: /var/www/${source_dir}/public
      APP_URL: "http://192.168.1.4:${port}"
      TRUSTED_PROXIES: "*"
      DB_HOST: database-service
      DB_USERNAME: ${db_user}
      DB_PASSWORD: ${db_pass}
      DB_DATABASE: ${database}
      SKIP_PUBLIC_SYNC: "true"
      AWS_ACCESS_KEY_ID: admin
      AWS_SECRET_ACCESS_KEY: password
      AWS_BUCKET: ${name}
      AWS_URL: http://192.168.1.4:9090/${name}
      AWS_ENDPOINT: http://minio:9090
    volumes:
      - ${name}_storage:/var/www/${source_dir}/storage
      - ${name}_bootstrap_cache:/var/www/${source_dir}/bootstrap/cache
      - ${name}_public:/var/www/${source_dir}/public
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: "1"
        reservations:
          memory: 512M
          cpus: "0.5"
COMPEOF

    if [ "${has_queue}" = "true" ]; then
        cat >> "$target" << COMPEOF

  queue:
    extends:
      file: ../base/php-base.yml
      service: php-worker-base
    image: ${image}:${version}
    container_name: ${name}-queue
    working_dir: /var/www/${source_dir}
    env_file:
      - ../../apps/${name}/.env.example
    environment:
      DB_HOST: database-service
      DB_USERNAME: ${db_user}
      DB_PASSWORD: ${db_pass}
    volumes:
      - ${name}_storage:/var/www/${source_dir}/storage
      - ${name}_bootstrap_cache:/var/www/${source_dir}/bootstrap/cache
    command: >
      artisan queue:work
        --sleep=5
        --tries=3
        --timeout=120
        --max-jobs=500
        --max-time=3600
    deploy:
      resources:
        limits:
          memory: 384M
          cpus: "0.5"
        reservations:
          memory: 128M
          cpus: "0.25"
COMPEOF
    fi

    if [ "${has_scheduler}" = "true" ]; then
        cat >> "$target" << COMPEOF

  scheduler:
    extends:
      file: ../base/php-base.yml
      service: php-scheduler-base
    image: ${image}:${version}
    container_name: ${name}-scheduler
    working_dir: /var/www/${source_dir}
    env_file:
      - ../../apps/${name}/.env.example
    environment:
      DB_HOST: database-service
      DB_USERNAME: ${db_user}
      DB_PASSWORD: ${db_pass}
    volumes:
      - ${name}_storage:/var/www/${source_dir}/storage
      - ${name}_bootstrap_cache:/var/www/${source_dir}/bootstrap/cache
    command: >
      artisan schedule:work
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: "0.2"
        reservations:
          memory: 64M
          cpus: "0.1"
COMPEOF
    fi

    log_success "  Created compose/apps/${name}.yml"
}

# ============================================
# Generate Dockerfile
# ============================================
gen_dockerfile() {
    local name="$1" source_dir="$2" desc="$3"
    local target="${PROJECT_DIR}/apps/${name}/Dockerfile"
    local app_name="${desc%% -*}"
    app_name="${app_name%% -}"

    log_info "  apps/${name}/Dockerfile"

    cat > "$target" << DOCKEREOF
# ============================================
# Production ${app_name} Image for Docker Hub
# Optimized: Build once, use 3x (app/queue/scheduler)
# ============================================
FROM php:8.4-fpm-alpine AS base

ARG UID=1000
ARG GID=1000
ARG TZ=Asia/Jakarta
ARG APP_NAME="${app_name}"

# Install system dependencies and PHP extensions
RUN apk add --no-cache \
      tzdata bash shadow ca-certificates unzip \
      icu-dev oniguruma-dev libzip-dev zlib-dev \
      libpng-dev libjpeg-turbo-dev freetype-dev \
      libxml2-dev postgresql-dev \
      linux-headers \
      curl openssl \
      mariadb-client \
      su-exec \
      \$PHPIZE_DEPS \
  && cp /usr/share/zoneinfo/\${TZ} /etc/localtime \
  && echo "\${TZ}" > /etc/timezone \
  && docker-php-ext-configure intl \
  && docker-php-ext-configure gd --with-freetype --with-jpeg \
  && docker-php-ext-install -j"\$(nproc)" \
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
  && pecl install igbinary apcu \
  && docker-php-ext-enable igbinary apcu \
  && apk del --no-network \$PHPIZE_DEPS linux-headers \
  && rm -rf /var/cache/apk/* /tmp/*

# Copy composer binary
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Create non-root user
RUN addgroup -g "\${GID}" www \
  && adduser -D -G www -u "\${UID}" www \
  && sed -ri 's/^user = .*/user = www/' /usr/local/etc/php-fpm.d/www.conf \
  && sed -ri 's/^group = .*/group = www/' /usr/local/etc/php-fpm.d/www.conf

ENV APP_NAME=\${APP_NAME}

# ============================================
# Stage 2: Build & Dependencies
# ============================================
FROM base AS builder

ARG APP_DIR=${source_dir}

ENV COMPOSER_CACHE_DIR=/tmp/composer-cache \
    COMPOSER_MEMORY_LIMIT=-1 \
    COMPOSER_NO_INTERACTION=1

WORKDIR /build

COPY site/\${APP_DIR}/composer.json site/\${APP_DIR}/composer.lock* ./

RUN set -eux; \
    composer install \
      --no-dev \
      --prefer-dist \
      --no-interaction \
      --no-progress \
      --no-scripts \
      --optimize-autoloader \
      --classmap-authoritative; \
    rm -rf "\$COMPOSER_CACHE_DIR"

COPY site/\${APP_DIR}/ ./

RUN set -eux; \
    composer dump-autoload --optimize --classmap-authoritative --no-scripts 2>/dev/null || true; \
    if [ -f .env ]; then \
      php artisan optimize 2>/dev/null || true; \
    fi; \
    if [ -d vendor/livewire ]; then \
      echo "✅ Livewire verified"; \
    else \
      echo "⚠️ Livewire not found in dependencies"; \
    fi

# ============================================
# Stage 3: Runtime (Final Image)
# ============================================
FROM base AS runtime

ARG TZ=Asia/Jakarta
ARG APP_NAME="${app_name}"

ENV APP_ENV=production \
    APP_WORKDIR=/var/www/${source_dir} \
    PHP_OPCACHE_VALIDATE_TIMESTAMPS=0 \
    PHP_MEMORY_LIMIT=512M \
    APP_NAME=\${APP_NAME}

WORKDIR \${APP_WORKDIR}

RUN set -eux; \
  { \
    echo "memory_limit=\${PHP_MEMORY_LIMIT}"; \
    echo "upload_max_filesize=64M"; \
    echo "post_max_size=64M"; \
    echo "max_execution_time=120"; \
    echo "max_input_time=120"; \
    echo "max_input_vars=3000"; \
    echo "date.timezone=\${TZ}"; \
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
    echo "opcache.validate_timestamps=\${PHP_OPCACHE_VALIDATE_TIMESTAMPS}"; \
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

COPY --from=builder --chown=www:www /build \${APP_WORKDIR}

RUN set -eux; \
    mkdir -p storage/framework/cache/data \
             storage/framework/sessions \
             storage/framework/views \
             storage/framework/testing \
             storage/logs \
             storage/app/public \
             bootstrap/cache; \
    chown -R www:www storage bootstrap/cache; \
    chmod -R ug+rwX storage bootstrap/cache; \
    chmod -R 775 storage/framework/views; \
    if [ -d public ]; then chmod -R 755 public; fi

COPY docker/php/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 9000

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD php -r "exit(extension_loaded('opcache') ? 0 : 1);"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php-fpm", "-F"]
DOCKEREOF

    log_success "  Created apps/${name}/Dockerfile"
}

# ============================================
# Generate .env.example
# ============================================
gen_env_example() {
    local name="$1" port="$2" db_user="$3" db_pass="$4" database="$5"
    local target="${PROJECT_DIR}/apps/${name}/.env.example"

    log_info "  apps/${name}/.env.example"

    cat > "$target" << ENVEOF
# ===========================================
# PRODUCTION ENVIRONMENT CONFIGURATION
# ===========================================

# Application
APP_NAME="${name}"
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=http://192.168.1.4:${port}

# Database
DB_CONNECTION=mysql
DB_HOST=database-service
DB_PORT=3306
DB_DATABASE=${database}
DB_USERNAME=${db_user}
DB_PASSWORD=${db_pass}

# Redis
REDIS_HOST=redis
REDIS_PASSWORD=null
REDIS_PORT=6379

# Cache & Queue
CACHE_DRIVER=file
QUEUE_CONNECTION=database
SESSION_DRIVER=database
SESSION_LIFETIME=120

# Mail
MAIL_MAILER=smtp
MAIL_HOST=smtp.example.com
MAIL_PORT=587
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=noreply@your-domain.com
MAIL_FROM_NAME="\${APP_NAME}"

# Storage
AWS_ACCESS_KEY_ID=admin
AWS_SECRET_ACCESS_KEY=password
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET=${name}
AWS_ENDPOINT=http://minio:9090
AWS_URL=http://192.168.1.4:9090/${name}
AWS_USE_PATH_STYLE_ENDPOINT=true

# Logging
LOG_CHANNEL=stack
LOG_LEVEL=debug
ENVEOF

    log_success "  Created apps/${name}/.env.example"
}

# ============================================
# Append to repos.csv
# ============================================
append_repos_csv() {
    local name="$1" source_dir="$2" repo="$3" branch="$4"
    local has_prod_env="$5" has_deps="$6" desc="$7"
    local prod_flag="no" deps_flag="no"
    [ "${has_prod_env}" = "true" ] && prod_flag="yes"
    [ "${has_deps}" = "true" ] && deps_flag="yes"

    local target="${PROJECT_DIR}/repos.csv"

    echo "${name},${source_dir},${repo},${branch},${prod_flag},${deps_flag},${desc}" >> "$target"
    log_success "  Appended to repos.csv"
}

# ============================================
# Append server block to nginx config
# ============================================
append_nginx_conf() {
    local name="$1" source_dir="$2" port="$3" desc="$4"
    local target="${PROJECT_DIR}/docker/nginx/nginx-multi-apps.conf"

    log_info "  docker/nginx/nginx-multi-apps.conf"

    # Find where to insert — before the last closing lines, or append to end
    # We'll insert right before the final blank server block markers
    # First remove the trailing empty server blocks if they exist
    sed -i '/^# =========================$/,/^}$/d' "$target" 2>/dev/null || true

    # Remove trailing blank lines
    sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$target" 2>/dev/null || true

    cat >> "$target" << NGINXEOF

# =========================
# ${desc} (Port ${port})
# =========================
server {
    listen ${port};
    server_name _;
    root /var/www/${source_dir}/public;
    index index.php index.html index.htm;

    client_max_body_size 100M;

    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Access-Control-Allow-Origin "*" always;
    add_header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, PATCH, OPTIONS" always;
    add_header Access-Control-Allow-Headers "Content-Type, Authorization, X-Requested-With, Accept" always;
    add_header Access-Control-Max-Age "3600" always;

    if (\$request_method = 'OPTIONS') {
        return 204;
    }

    location /health {
        access_log off;
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }

    location ~* ^/(build|assets)/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }

    location ^~ /livewire/ {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~* \\.(css|js|jpg|jpeg|png|gif|svg|webp|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        try_files \$uri =404;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \\.php\$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\\.php)(/.+)\$;
        fastcgi_pass app-${name}:9000;
        fastcgi_read_timeout 3600;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$fastcgi_path_info;
        fastcgi_param HTTP_X_FORWARDED_FOR \$remote_addr;
        fastcgi_param HTTP_X_FORWARDED_PROTO \$scheme;
        fastcgi_param HTTP_X_FORWARDED_HOST \$server_name;
        send_timeout 3600;
        proxy_connect_timeout 3600;
        proxy_read_timeout 3600;
        proxy_send_timeout 3600;
    }

    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    access_log /var/log/nginx/${name}_access.log main;
    error_log /var/log/nginx/${name}_error.log warn;
}
NGINXEOF

    log_success "  Server block appended to nginx-multi-apps.conf"
}

# ============================================
# Append SQL init for database
# ============================================
append_sql_init() {
    local name="$1" database="$2" db_user="$3" db_password="$4"
    local target="${PROJECT_DIR}/docker/db/sql/00-init-multi-db.sql"

    log_info "  docker/db/sql/00-init-multi-db.sql"

    cat >> "$target" << SQLEOF

-- =================================================
--  ${name} Database
-- =================================================
CREATE DATABASE IF NOT EXISTS ${database}
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${db_user}'@'%'
  IDENTIFIED BY '${db_password}';

GRANT ALL PRIVILEGES
  ON ${database}.* TO '${db_user}'@'%';

CREATE USER IF NOT EXISTS '${db_user}_readonly'@'%'
  IDENTIFIED BY '${name}@ReadOnly2025!';

GRANT SELECT ON ${database}.* TO '${db_user}_readonly'@'%';
SQLEOF

    # Ensure FLUSH PRIVILEGES stays at the end
    # Remove any duplicate FLUSH and re-append at the end
    local flush_lines
    flush_lines=$(grep -c "FLUSH PRIVILEGES" "$target" 2>/dev/null || echo "0")
    if [ "$flush_lines" -gt 1 ]; then
        # Remove last line (the flush) and all trailing whitespace
        head -n -1 "$target" > "${target}.tmp"
        mv "${target}.tmp" "$target"
        # Trim trailing blank lines
        sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$target" 2>/dev/null || true
        echo "" >> "$target"
        echo "FLUSH PRIVILEGES;" >> "$target"
    fi

    log_success "  SQL init appended"
}

# ============================================
# Update env files
# ============================================
append_env_files() {
    local name="$1" port="$2"
    local name_upper
    name_upper=$(echo "$name" | tr '[:lower:]' '[:upper:]')

    for env_file in "${PROJECT_DIR}/env/prod.env" "${PROJECT_DIR}/env/dev.env"; do
        if [ -f "$env_file" ]; then
            # Insert before the last line (which is often blank or the last var)
            # or at the end after last meaningful content
            local entry="${name_upper}_HOST_PORT=${port}"
            if grep -q "^${entry}$" "$env_file" 2>/dev/null; then
                log_warn "  ${entry} already exists in $(basename $env_file), skipping"
            else
                # Insert before trailing blank lines at end
                local tmpfile
                tmpfile=$(mktemp)
                # Remove trailing blank lines, add our entry, then one blank line
                sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$env_file" > "$tmpfile"
                echo "" >> "$tmpfile"
                echo "# ${name}" >> "$tmpfile"
                echo "${entry}" >> "$tmpfile"
                mv "$tmpfile" "$env_file"
                log_success "  Added ${entry} to $(basename $env_file)"
            fi
        fi
    done
}

# ============================================
# Update rsch help
# ============================================
update_rsch_help() {
    local name="$1" port="$2" desc="$3"
    local target="${PROJECT_DIR}/rsch"

    # Check if already exists in help
    if grep -q "^    ${name}[[:space:]]" "$target" 2>/dev/null; then
        log_warn "  ${name} already in rsch help, skipping"
        return
    fi

    sed -i "/^APPS:/a\    ${name}\t — ${desc} (port ${port})" "$target"
    log_success "  Added to rsch help"
}

# ============================================
# Main (when called directly, not sourced)
# ============================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -eq 0 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        echo "Usage: scripts/scaffold.sh <app-name> [--auto]"
        echo ""
        echo "  <app-name>   Scaffold a new app (interactive)"
        echo "  --auto        Read apps/<name>/app.yml and generate silently"
        exit 0
    fi

    if [ "${2:-}" = "--auto" ]; then
        # Read from app.yml and generate
        local app_yml="${PROJECT_DIR}/apps/${1}/app.yml"
        if [ ! -f "$app_yml" ]; then
            log_error "File not found: ${app_yml}"
            exit 1
        fi
        scaffold_generate_all \
            "$1" \
            "$(grep -E "^source_dir:" "$app_yml" | sed 's/^[^:]*:[[:space:]]*//')" \
            "$(grep -E "^image:" "$app_yml" | sed 's/^[^:]*:[[:space:]]*//')" \
            "$(grep -E "^version:" "$app_yml" | sed 's/^[^:]*:[[:space:]]*//')" \
            "$(grep -E "^port:" "$app_yml" | sed 's/^[^:]*:[[:space:]]*//')" \
            "$(grep -E "^database:" "$app_yml" | sed 's/^[^:]*:[[:space:]]*//')" \
            "$(grep -E "^db_user:" "$app_yml" | sed 's/^[^:]*:[[:space:]]*//')" \
            "$(grep -E "^db_password:" "$app_yml" | sed 's/^[^:]*:[[:space:]]*//')" \
            "$(grep -E "^description:" "$app_yml" | sed 's/^[^:]*:[[:space:]]*//')" \
            "$(grep -E "^queue:" "$app_yml" | sed 's/^[^:]*:[[:space:]]*//')" \
            "$(grep -E "^scheduler:" "$app_yml" | sed 's/^[^:]*:[[:space:]]*//')" \
            "$(grep -E "^repo:" "$app_yml" | sed 's/^[^:]*:[[:space:]]*//')" \
            "$(grep -E "^branch:" "$app_yml" | sed 's/^[^:]*:[[:space:]]*//')" \
            "$(grep -E "^has_prod_env:" "$app_yml" | sed 's/^[^:]*:[[:space:]]*//')" \
            "$(grep -E "^has_local_deps:" "$app_yml" | sed 's/^[^:]*:[[:space:]]*//')"
    else
        scaffold_interactive "$1"
    fi
fi
