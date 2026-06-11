#!/usr/bin/env bash
# =============================================================================
# rsch scaffold v2
# Generate Docker config for a new app using templates.
#
# Usage:
#   ./scripts/scaffold.sh new rbv
#   ./scripts/scaffold.sh new rbv --auto
#   ./scripts/scaffold.sh render rbv
#   ./scripts/scaffold.sh list
#
# Main idea:
#   - Bash only orchestrates.
#   - YAML/Nginx/SQL/env content lives in templates/scaffold/*.tpl.
#   - App metadata lives in apps/<name>/app.yml.
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Path
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_DIR="${PROJECT_DIR}/scripts/templates/scaffold"

# -----------------------------------------------------------------------------
# Color & log
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error()   { echo -e "${RED}❌ $1${NC}" >&2; }
log_header()  {
  echo -e "\n${CYAN}════════════════════════════════════════════${NC}"
  echo -e "${CYAN}   $1${NC}"
  echo -e "${CYAN}════════════════════════════════════════════${NC}"
}

die() {
  log_error "$1"
  exit 1
}

# -----------------------------------------------------------------------------
# Basic helpers
# -----------------------------------------------------------------------------
usage() {
  cat <<'EOF'
Usage:
  ./scripts/scaffold.sh new <app>          Create apps/<app>/app.yml interactively, then render files
  ./scripts/scaffold.sh new <app> --auto   Render from existing apps/<app>/app.yml
  ./scripts/scaffold.sh render <app>       Render from existing apps/<app>/app.yml
  ./scripts/scaffold.sh list               Show available scaffold templates
  ./scripts/scaffold.sh check              Check required files/templates

Examples:
  ./scripts/scaffold.sh new rbv
  ./scripts/scaffold.sh new rbv --auto
  ./scripts/scaffold.sh render rbv
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Command not found: $1"
}

to_upper() {
  echo "$1" | tr '[:lower:]' '[:upper:]' | tr '-' '_'
}

to_lower() {
  echo "$1" | tr '[:upper:]' '[:lower:]'
}

trim() {
  sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

ensure_dir() {
  mkdir -p "$1"
}

file_exists() {
  [ -f "$1" ]
}

# -----------------------------------------------------------------------------
# Simple YAML reader
# Supports simple "key: value" only.
# Good enough for apps/<name>/app.yml.
# -----------------------------------------------------------------------------
yaml_get() {
  local file="$1"
  local key="$2"

  grep -E "^${key}:" "$file" 2>/dev/null \
    | head -n1 \
    | sed 's/^[^:]*:[[:space:]]*//' \
    | sed 's/^"//;s/"$//' \
    | sed "s/^'//;s/'$//" \
    | trim
}

yaml_bool() {
  local value
  value="$(to_lower "${1:-false}")"

  case "$value" in
    true|yes|y|1) echo "true" ;;
    *) echo "false" ;;
  esac
}

# -----------------------------------------------------------------------------
# Template rendering
# Replaces {{VAR}} placeholders using exported environment variables.
# No external envsubst dependency needed.
# -----------------------------------------------------------------------------
render_template() {
  local template="$1"
  local output="$2"

  [ -f "$template" ] || die "Template not found: $template"

  ensure_dir "$(dirname "$output")"

  python3 - "$template" "$output" <<'PY'
import os
import re
import sys

template_path = sys.argv[1]
output_path = sys.argv[2]

with open(template_path, "r", encoding="utf-8") as f:
    content = f.read()

pattern = re.compile(r"\{\{([A-Z0-9_]+)\}\}")

def replace(match):
    key = match.group(1)
    return os.environ.get(key, "")

content = pattern.sub(replace, content)

with open(output_path, "w", encoding="utf-8") as f:
    f.write(content)
PY
}

render_template_to_stdout() {
  local template="$1"

  [ -f "$template" ] || die "Template not found: $template"

  python3 - "$template" <<'PY'
import os
import re
import sys

template_path = sys.argv[1]

with open(template_path, "r", encoding="utf-8") as f:
    content = f.read()

pattern = re.compile(r"\{\{([A-Z0-9_]+)\}\}")

def replace(match):
    key = match.group(1)
    return os.environ.get(key, "")

print(pattern.sub(replace, content), end="")
PY
}

# -----------------------------------------------------------------------------
# Safe append helpers
# -----------------------------------------------------------------------------
append_once() {
  local target="$1"
  local marker="$2"
  local content="$3"

  ensure_dir "$(dirname "$target")"
  touch "$target"

  if grep -qF "$marker" "$target"; then
    log_warn "  Skip, already exists in ${target}: ${marker}"
    return 0
  fi

  {
    echo ""
    echo "$content"
  } >> "$target"
}

insert_before_marker_once() {
  local target="$1"
  local marker="$2"
  local exists_marker="$3"
  local content="$4"

  [ -f "$target" ] || die "Target not found: $target"

  if grep -qF "$exists_marker" "$target"; then
    log_warn "  Skip, already exists in ${target}: ${exists_marker}"
    return 0
  fi

  if ! grep -qF "$marker" "$target"; then
    die "Marker not found in ${target}: ${marker}"
  fi

  local tmp
  tmp="$(mktemp)"

  awk -v marker="$marker" -v block="$content" '
    index($0, marker) && inserted == 0 {
      print block
      inserted = 1
    }
    { print }
  ' "$target" > "$tmp"

  mv "$tmp" "$target"
}

insert_after_marker_once() {
  local target="$1"
  local marker="$2"
  local exists_marker="$3"
  local content="$4"

  [ -f "$target" ] || die "Target not found: $target"

  if grep -qF "$exists_marker" "$target"; then
    log_warn "  Skip, already exists in ${target}: ${exists_marker}"
    return 0
  fi

  if ! grep -qF "$marker" "$target"; then
    die "Marker not found in ${target}: ${marker}"
  fi

  local tmp
  tmp="$(mktemp)"

  awk -v marker="$marker" -v block="$content" '
    {
      print
      if (index($0, marker) && inserted == 0) {
        print block
        inserted = 1
      }
    }
  ' "$target" > "$tmp"

  mv "$tmp" "$target"
}

append_env_once() {
  local target="$1"
  local key="$2"
  local value="$3"
  local label="$4"

  ensure_dir "$(dirname "$target")"
  touch "$target"

  if grep -qE "^${key}=" "$target"; then
    log_warn "  ${key} already exists in $(basename "$target"), skipping"
    return 0
  fi

  {
    echo ""
    echo "# ${label}"
    echo "${key}=${value}"
  } >> "$target"
}

append_csv_once() {
  local target="$1"
  local app_name="$2"
  local row="$3"

  ensure_dir "$(dirname "$target")"
  touch "$target"

  if grep -qE "^${app_name}," "$target"; then
    log_warn "  ${app_name} already exists in repos.csv, skipping"
    return 0
  fi

  echo "$row" >> "$target"
}

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------
required_templates=(
  "app-yml.tpl"
  "compose-app.yml.tpl"
  "compose-main-services.yml.tpl"
  "compose-main-volumes.yml.tpl"
  "compose-web-port.yml.tpl"
  "compose-web-volume.yml.tpl"
  "nginx-app.conf.tpl"
  "build-service.yml.tpl"
  "env-example.tpl"
  "sql-init.tpl"
)

check_requirements() {
  log_header "Checking scaffold requirements"

  require_cmd python3
  require_cmd grep
  require_cmd sed
  require_cmd awk

  [ -d "$TEMPLATE_DIR" ] || die "Template directory not found: $TEMPLATE_DIR"

  for tpl in "${required_templates[@]}"; do
    if [ -f "${TEMPLATE_DIR}/${tpl}" ]; then
      log_success "Template found: ${tpl}"
    else
      log_error "Template missing: ${tpl}"
      return 1
    fi
  done

  log_success "All requirements OK"
}

list_templates() {
  log_header "Available templates"

  if [ ! -d "$TEMPLATE_DIR" ]; then
    log_warn "Template directory does not exist: $TEMPLATE_DIR"
    return 0
  fi

  find "$TEMPLATE_DIR" -maxdepth 1 -type f -name "*.tpl" -printf "  - %f\n" | sort
}

# -----------------------------------------------------------------------------
# Port detection
# -----------------------------------------------------------------------------
detect_next_port() {
  local highest_port=8300
  local p

  if [ -f "${PROJECT_DIR}/compose/base/web.yml" ]; then
    while read -r p; do
      [ -n "$p" ] || continue
      if [ "$p" -gt "$highest_port" ]; then
        highest_port="$p"
      fi
    done < <(grep -oP '\${[A-Z0-9_]+_HOST_PORT:-\K[0-9]+' "${PROJECT_DIR}/compose/base/web.yml" 2>/dev/null || true)
  fi

  for env_file in "${PROJECT_DIR}/env/prod.env" "${PROJECT_DIR}/env/dev.env" "${PROJECT_DIR}/env/local.env"; do
    [ -f "$env_file" ] || continue

    while read -r p; do
      [ -n "$p" ] || continue
      if [ "$p" -gt "$highest_port" ]; then
        highest_port="$p"
      fi
    done < <(grep -oP 'HOST_PORT=\K[0-9]+' "$env_file" 2>/dev/null || true)
  done

  echo $((highest_port + 10))
}

# -----------------------------------------------------------------------------
# Load app config and export variables for templates
# -----------------------------------------------------------------------------
load_app_config() {
  local app_name="$1"
  local app_yml="${PROJECT_DIR}/apps/${app_name}/app.yml"

  [ -f "$app_yml" ] || die "App config not found: $app_yml"

  APP_NAME="$(yaml_get "$app_yml" "name")"
  APP_NAME="${APP_NAME:-$app_name}"

  APP_DESC="$(yaml_get "$app_yml" "description")"
  APP_DESC="${APP_DESC:-${APP_NAME} - Application}"

  APP_REPO="$(yaml_get "$app_yml" "repo")"
  APP_REPO="${APP_REPO:-https://github.com/juniyasyos/${APP_NAME}.git}"

  APP_BRANCH="$(yaml_get "$app_yml" "branch")"
  APP_BRANCH="${APP_BRANCH:-main}"

  SOURCE_DIR="$(yaml_get "$app_yml" "source_dir")"
  SOURCE_DIR="${SOURCE_DIR:-$APP_NAME}"

  IMAGE_NAME="$(yaml_get "$app_yml" "image")"
  IMAGE_NAME="${IMAGE_NAME:-juniyasyos/${APP_NAME}}"

  IMAGE_VERSION="$(yaml_get "$app_yml" "version")"
  IMAGE_VERSION="${IMAGE_VERSION:-v1.0.0}"

  APP_PORT="$(yaml_get "$app_yml" "port")"
  APP_PORT="${APP_PORT:-$(detect_next_port)}"

  APP_DOMAIN="$(yaml_get "$app_yml" "domain")"
  APP_DOMAIN="${APP_DOMAIN:-${APP_NAME}.local}"

  DB_NAME="$(yaml_get "$app_yml" "database")"
  DB_NAME="${DB_NAME:-${APP_NAME}_db}"

  DB_USER="$(yaml_get "$app_yml" "db_user")"
  DB_USER="${DB_USER:-${APP_NAME}_user}"

  DB_PASSWORD="$(yaml_get "$app_yml" "db_password")"
  DB_PASSWORD="${DB_PASSWORD:-${APP_NAME}_password}"

  HAS_QUEUE="$(yaml_bool "$(yaml_get "$app_yml" "queue")")"
  HAS_SCHEDULER="$(yaml_bool "$(yaml_get "$app_yml" "scheduler")")"
  HAS_PROD_ENV="$(yaml_bool "$(yaml_get "$app_yml" "has_prod_env")")"
  HAS_LOCAL_DEPS="$(yaml_bool "$(yaml_get "$app_yml" "has_local_deps")")"

  PHP_VERSION="$(yaml_get "$app_yml" "php_version")"
  PHP_VERSION="${PHP_VERSION:-8.4}"

  APP_UPPER="$(to_upper "$APP_NAME")"
  APP_LOWER="$(to_lower "$APP_NAME")"

  HOST_PORT_VAR="${APP_UPPER}_HOST_PORT"

  # Standard shared volume names.
  # These names must match compose/base/web.yml and infra volumes.
  PUBLIC_VOLUME_NAME="base_${APP_NAME}_public"
  STORAGE_VOLUME_NAME="base_${APP_NAME}_storage"
  BOOTSTRAP_CACHE_VOLUME_NAME="base_${APP_NAME}_bootstrap_cache"

  # Service aliases expected by nginx fastcgi_pass.
  APP_SERVICE_ALIAS="app-${APP_NAME}"
  QUEUE_SERVICE_ALIAS="queue-${APP_NAME}"
  SCHEDULER_SERVICE_ALIAS="scheduler-${APP_NAME}"

  # Flags for optional template chunks
  if [ "$HAS_QUEUE" = "true" ] && [ -f "${TEMPLATE_DIR}/compose-main-queue-service.yml.tpl" ]; then
    QUEUE_MAIN_SERVICE="$(render_template_to_stdout "${TEMPLATE_DIR}/compose-main-queue-service.yml.tpl" 2>/dev/null || true)"
  else
    QUEUE_MAIN_SERVICE=""
  fi

  if [ "$HAS_SCHEDULER" = "true" ] && [ -f "${TEMPLATE_DIR}/compose-main-scheduler-service.yml.tpl" ]; then
    SCHEDULER_MAIN_SERVICE="$(render_template_to_stdout "${TEMPLATE_DIR}/compose-main-scheduler-service.yml.tpl" 2>/dev/null || true)"
  else
    SCHEDULER_MAIN_SERVICE=""
  fi

  export \
    APP_NAME APP_DESC APP_REPO APP_BRANCH SOURCE_DIR IMAGE_NAME IMAGE_VERSION \
    APP_PORT APP_DOMAIN DB_NAME DB_USER DB_PASSWORD HAS_QUEUE HAS_SCHEDULER \
    HAS_PROD_ENV HAS_LOCAL_DEPS PHP_VERSION APP_UPPER APP_LOWER HOST_PORT_VAR \
    PUBLIC_VOLUME_NAME STORAGE_VOLUME_NAME BOOTSTRAP_CACHE_VOLUME_NAME \
    APP_SERVICE_ALIAS QUEUE_SERVICE_ALIAS SCHEDULER_SERVICE_ALIAS \
    QUEUE_MAIN_SERVICE SCHEDULER_MAIN_SERVICE
}

show_app_summary() {
  cat <<EOF

╔═══════════════════════════════════════════════════════════════╗
║  Ringkasan App                                               
╠═══════════════════════════════════════════════════════════════╣
║  App:        ${APP_NAME}
║  Desc:       ${APP_DESC}
║  Repo:       ${APP_REPO}
║  Branch:     ${APP_BRANCH}
║  Source:     ${SOURCE_DIR}
║  Image:      ${IMAGE_NAME}:${IMAGE_VERSION}
║  Port:       ${APP_PORT}
║  Domain:     ${APP_DOMAIN}
║  Database:   ${DB_NAME}
║  DB User:    ${DB_USER}
║  Queue:      ${HAS_QUEUE}
║  Scheduler:  ${HAS_SCHEDULER}
║  Prod env:   ${HAS_PROD_ENV}
║  Local deps: ${HAS_LOCAL_DEPS}
╚═══════════════════════════════════════════════════════════════╝

EOF
}

# -----------------------------------------------------------------------------
# Create apps/<name>/app.yml interactively
# -----------------------------------------------------------------------------
create_app_yml_interactive() {
  local app_name="$1"
  local app_dir="${PROJECT_DIR}/apps/${app_name}"
  local app_yml="${app_dir}/app.yml"

  log_header "New app: ${app_name}"

  if [ -f "$app_yml" ]; then
    log_warn "App config already exists: ${app_yml}"
    read -r -p "Overwrite app.yml? [y/N]: " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
      log_warn "Cancelled."
      exit 1
    fi
  fi

  local default_port
  default_port="$(detect_next_port)"

  local name desc repo branch source_dir image version port domain database db_user db_password
  local has_queue has_scheduler has_prod_env has_local_deps php_version

  echo ""
  echo "Isi detail aplikasi. Tekan Enter untuk memakai default."
  echo ""

  read -r -p "  Nama app       [${app_name}]: " name
  name="${name:-$app_name}"

  read -r -p "  Deskripsi      [${name} - Application]: " desc
  desc="${desc:-${name} - Application}"

  read -r -p "  Git repo URL   [https://github.com/juniyasyos/${name}.git]: " repo
  repo="${repo:-https://github.com/juniyasyos/${name}.git}"

  read -r -p "  Branch         [main]: " branch
  branch="${branch:-main}"

  read -r -p "  Source dir     [${name}]: " source_dir
  source_dir="${source_dir:-$name}"

  read -r -p "  Image name     [${name}]: " image
  image="${image:-$name}"

  read -r -p "  Version        [v1.0.0]: " version
  version="${version:-v1.0.0}"

  read -r -p "  Port           [${default_port}]: " port
  port="${port:-$default_port}"

  read -r -p "  Domain         [${name}.local]: " domain
  domain="${domain:-${name}.local}"

  read -r -p "  Database name  [${name}_db]: " database
  database="${database:-${name}_db}"

  read -r -p "  DB user        [${name}_user]: " db_user
  db_user="${db_user:-${name}_user}"

  read -r -p "  DB password    [${name}_password]: " db_password
  db_password="${db_password:-${name}_password}"

  read -r -p "  PHP version    [8.4]: " php_version
  php_version="${php_version:-8.4}"

  read -r -p "  Queue worker?  [Y/n]: " has_queue
  if [[ "$has_queue" =~ ^[Nn]$ ]]; then
    has_queue="false"
  else
    has_queue="true"
  fi

  read -r -p "  Scheduler?     [Y/n]: " has_scheduler
  if [[ "$has_scheduler" =~ ^[Nn]$ ]]; then
    has_scheduler="false"
  else
    has_scheduler="true"
  fi

  read -r -p "  Prod env?      [Y/n]: " has_prod_env
  if [[ "$has_prod_env" =~ ^[Nn]$ ]]; then
    has_prod_env="false"
  else
    has_prod_env="true"
  fi

  read -r -p "  Local deps?    [y/N]: " has_local_deps
  if [[ "$has_local_deps" =~ ^[Yy]$ ]]; then
    has_local_deps="true"
  else
    has_local_deps="false"
  fi

  export \
    APP_NAME="$name" \
    APP_DESC="$desc" \
    APP_REPO="$repo" \
    APP_BRANCH="$branch" \
    SOURCE_DIR="$source_dir" \
    IMAGE_NAME="$image" \
    IMAGE_VERSION="$version" \
    APP_PORT="$port" \
    APP_DOMAIN="$domain" \
    DB_NAME="$database" \
    DB_USER="$db_user" \
    DB_PASSWORD="$db_password" \
    HAS_QUEUE="$has_queue" \
    HAS_SCHEDULER="$has_scheduler" \
    HAS_PROD_ENV="$has_prod_env" \
    HAS_LOCAL_DEPS="$has_local_deps" \
    PHP_VERSION="$php_version"

  ensure_dir "$app_dir"

  render_template "${TEMPLATE_DIR}/app-yml.tpl" "$app_yml"

  log_success "Created apps/${name}/app.yml"

  load_app_config "$name"
  show_app_summary

  read -r -p "Generate Docker config now? [Y/n]: " confirm
  if [[ "$confirm" =~ ^[Nn]$ ]]; then
    log_warn "Only app.yml created."
    exit 0
  fi
}

# -----------------------------------------------------------------------------
# Render generated files
# -----------------------------------------------------------------------------
render_compose_app() {
  log_info "Generating compose/apps/${APP_NAME}.yml"

  render_template \
    "${TEMPLATE_DIR}/compose-app.yml.tpl" \
    "${PROJECT_DIR}/compose/apps/${APP_NAME}.yml"

  log_success "Created compose/apps/${APP_NAME}.yml"
}

render_env_example() {
  log_info "Generating apps/${APP_NAME}/.env.example"

  render_template \
    "${TEMPLATE_DIR}/env-example.tpl" \
    "${PROJECT_DIR}/apps/${APP_NAME}/.env.example"

  log_success "Created apps/${APP_NAME}/.env.example"
}

render_nginx_conf() {
  log_info "Generating docker/nginx/conf.d/${APP_NAME}.conf"

  render_template \
    "${TEMPLATE_DIR}/nginx-app.conf.tpl" \
    "${PROJECT_DIR}/docker/nginx/conf.d/${APP_NAME}.conf"

  log_success "Created docker/nginx/conf.d/${APP_NAME}.conf"
}

render_dockerfile() {
  local template="${PROJECT_DIR}/docker/php/Dockerfile.template"
  local target="${PROJECT_DIR}/apps/${APP_NAME}/Dockerfile"

  if [ ! -f "$template" ]; then
    log_warn "Dockerfile template not found: ${template}, skipping"
    return 0
  fi

  log_info "Generating apps/${APP_NAME}/Dockerfile"

  export DESCRIPTION="$APP_DESC"

  render_template "$template" "$target"

  log_success "Created apps/${APP_NAME}/Dockerfile"
}

append_to_compose_main() {
  local target="${PROJECT_DIR}/compose.yml"

  [ -f "$target" ] || {
    log_warn "compose.yml not found, skipping main compose update"
    return 0
  }

  log_info "Updating compose.yml"

  local service_block
  service_block="$(render_template_to_stdout "${TEMPLATE_DIR}/compose-main-services.yml.tpl")"

  local volume_block
  volume_block="$(render_template_to_stdout "${TEMPLATE_DIR}/compose-main-volumes.yml.tpl")"

  # Insert services before "# Named Volumes" if that marker exists.
  # This matches your current compose.yml style.
  insert_before_marker_once \
    "$target" \
    "# Named Volumes" \
    "app-${APP_NAME}:" \
    "$service_block"

  # Insert volumes before "networks:".
  insert_before_marker_once \
    "$target" \
    "networks:" \
    "${APP_NAME}_public:" \
    "$volume_block"

  log_success "compose.yml updated"
}

append_to_web_base() {
  local target="${PROJECT_DIR}/compose/base/web.yml"

  [ -f "$target" ] || {
    log_warn "compose/base/web.yml not found, skipping web compose update"
    return 0
  }

  log_info "Updating compose/base/web.yml"

  local port_block
  port_block="$(render_template_to_stdout "${TEMPLATE_DIR}/compose-web-port.yml.tpl")"

  local volume_block
  volume_block="$(render_template_to_stdout "${TEMPLATE_DIR}/compose-web-volume.yml.tpl")"

  insert_after_marker_once \
    "$target" \
    "x-web-ports:" \
    "\${${HOST_PORT_VAR}:-${APP_PORT}}:${APP_PORT}" \
    "$port_block"

  insert_after_marker_once \
    "$target" \
    "x-web-volumes:" \
    "${APP_NAME}_public:/var/www/${SOURCE_DIR}/public:ro" \
    "$volume_block"

  log_success "compose/base/web.yml updated"
}

append_to_build_compose() {
  local target="${PROJECT_DIR}/compose/build.yml"

  [ -f "$target" ] || {
    log_warn "compose/build.yml not found, skipping build compose update"
    return 0
  }

  log_info "Updating compose/build.yml"

  local build_block
  build_block="$(render_template_to_stdout "${TEMPLATE_DIR}/build-service.yml.tpl")"

  append_once \
    "$target" \
    "${APP_NAME}:" \
    "$build_block"

  log_success "compose/build.yml updated"
}

append_to_sql_init() {
  local target="${PROJECT_DIR}/docker/db/sql/00-init-multi-db.sql"

  log_info "Updating database init SQL"

  local sql_block
  sql_block="$(render_template_to_stdout "${TEMPLATE_DIR}/sql-init.tpl")"

  append_once \
    "$target" \
    "${DB_NAME} Database" \
    "$sql_block"

  # Keep FLUSH PRIVILEGES at the end.
  if [ -f "$target" ]; then
    sed -i '/^[[:space:]]*FLUSH PRIVILEGES;[[:space:]]*$/d' "$target"
    {
      echo ""
      echo "FLUSH PRIVILEGES;"
    } >> "$target"
  fi

  log_success "docker/db/sql/00-init-multi-db.sql updated"
}

append_to_repos_csv() {
  local target="${PROJECT_DIR}/repos.csv"
  local prod_flag="no"
  local deps_flag="no"

  [ "$HAS_PROD_ENV" = "true" ] && prod_flag="yes"
  [ "$HAS_LOCAL_DEPS" = "true" ] && deps_flag="yes"

  local row="${APP_NAME},${SOURCE_DIR},${APP_REPO},${APP_BRANCH},${prod_flag},${deps_flag},${APP_DESC}"

  log_info "Updating repos.csv"

  append_csv_once "$target" "$APP_NAME" "$row"

  log_success "repos.csv updated"
}

append_to_env_files() {
  local key="${HOST_PORT_VAR}"
  local value="${APP_PORT}"

  log_info "Updating env files"

  for env_file in "${PROJECT_DIR}/env/prod.env" "${PROJECT_DIR}/env/dev.env" "${PROJECT_DIR}/env/local.env"; do
    if [ -f "$env_file" ]; then
      append_env_once "$env_file" "$key" "$value" "$APP_NAME"
      log_success "$(basename "$env_file") updated"
    fi
  done
}

update_rsch_help() {
  local target="${PROJECT_DIR}/rsch"

  [ -f "$target" ] || {
    log_warn "rsch script not found, skipping help update"
    return 0
  }

  if grep -qE "^[[:space:]]+${APP_NAME}[[:space:]]" "$target"; then
    log_warn "  ${APP_NAME} already exists in rsch help, skipping"
    return 0
  fi

  if grep -q "^APPS:" "$target"; then
    sed -i "/^APPS:/a\    ${APP_NAME}\t — ${APP_DESC} (port ${APP_PORT})" "$target"
    log_success "rsch help updated"
  else
    log_warn "APPS marker not found in rsch, skipping help update"
  fi
}

# -----------------------------------------------------------------------------
# Main render pipeline
# -----------------------------------------------------------------------------
render_all() {
  local app_name="$1"

  check_requirements >/dev/null

  load_app_config "$app_name"
  show_app_summary

  log_header "Generating Docker config for ${APP_NAME}"

  ensure_dir "${PROJECT_DIR}/compose/apps"
  ensure_dir "${PROJECT_DIR}/docker/nginx/conf.d"
  ensure_dir "${PROJECT_DIR}/docker/db/sql"
  ensure_dir "${PROJECT_DIR}/apps/${APP_NAME}"

  render_compose_app
  render_env_example
  render_nginx_conf
  render_dockerfile

  append_to_compose_main
  append_to_web_base
  append_to_build_compose
  append_to_sql_init
  append_to_repos_csv
  append_to_env_files
  update_rsch_help

  log_header "Done"
  log_success "Generated config for ${APP_NAME}"

  cat <<EOF

Next check:

  docker compose -f compose/apps/${APP_NAME}.yml config
  docker compose -f compose.yml config | grep -A30 "${APP_NAME}_public"
  docker compose -f compose/base/infra.yml config | grep -A30 "${APP_NAME}_public"

Expected shared volumes:

  ${APP_NAME}_public  -> ${PUBLIC_VOLUME_NAME}
  ${APP_NAME}_storage -> ${STORAGE_VOLUME_NAME}

EOF
}

# -----------------------------------------------------------------------------
# Command router
# -----------------------------------------------------------------------------
main() {
  local command="${1:-}"

  case "$command" in
    new)
      local app_name="${2:-}"
      local mode="${3:-}"

      [ -n "$app_name" ] || die "App name is required."

      if [ "$mode" = "--auto" ]; then
        render_all "$app_name"
      else
        create_app_yml_interactive "$app_name"
        render_all "$APP_NAME"
      fi
      ;;

    render)
      local app_name="${2:-}"
      [ -n "$app_name" ] || die "App name is required."
      render_all "$app_name"
      ;;

    list)
      list_templates
      ;;

    check)
      check_requirements
      ;;

    ""|--help|-h|help)
      usage
      ;;

    *)
      usage
      die "Unknown command: $command"
      ;;
  esac
}

# -----------------------------------------------------------------------------
# Backward compatibility
# -----------------------------------------------------------------------------
# Old usage:
#   ./scripts/scaffold.sh smsp
#   ./scripts/scaffold.sh smsp --auto
#
# New usage:
#   ./scripts/scaffold.sh new smsp
#   ./scripts/scaffold.sh render smsp
# -----------------------------------------------------------------------------
# Only run main when executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [ $# -ge 1 ]; then
    case "${1:-}" in
      new|render|list|check|help|--help|-h)
        main "$@"
        ;;
      *)
        # Compatibility mode for old callers such as:
        #   ./rsch prepare smsp
        if [ "${2:-}" = "--auto" ]; then
          main new "$1" --auto
        else
          main new "$1"
        fi
        ;;
    esac
  else
    main "$@"
  fi
fi