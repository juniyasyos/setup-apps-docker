#!/usr/bin/env bash
# diagnose-signatory.sh
# Purpose: diagnose why App\Services\SignatoryService is not detected inside the
# `app-siimut` container and optionally perform temporary fixes or trigger a rebuild.
# Usage: ./diagnose-signatory.sh [--fix] [--rebuild] [-f <compose-file>] [-c <container>]

set -o errexit
set -o pipefail
set -o nounset

COMPOSE_FILE="./docker-compose-multi-apps.yml"
CONTAINER="app-siimut"
FIX=0
REBUILD=0

usage(){
  cat <<EOF
Usage: $0 [options]
Options:
  --fix           Run temporary fixes inside running container (composer dump-autoload, clear caches)
  --rebuild       Build & push image (calls ./build-push-dev.sh if present) and restart container
  -f <file>       Use alternate docker-compose file (default: ${COMPOSE_FILE})
  -c <container>  Use alternate container name (default: ${CONTAINER})
  -h              Show this help

Examples:
  $0                      # run read-only checks
  $0 --fix                # run checks then regenerate autoload + clear caches
  $0 --rebuild            # trigger image build/push and restart (asks confirmation)
EOF
}

# simple logger
info(){ printf "[INFO] %s\n" "$*"; }
warn(){ printf "[WARN] %s\n" "$*"; }
err(){ printf "[ERROR] %s\n" "$*"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix) FIX=1; shift ;;
    --rebuild) REBUILD=1; shift ;;
    -f) COMPOSE_FILE="$2"; shift 2 ;;
    -c) CONTAINER="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown arg: $1"; usage; exit 2 ;;
  esac
done

DCMD=(docker compose -f "$COMPOSE_FILE")

run_in_container(){
  "${DCMD[@]}" exec -T "$CONTAINER" bash -lc "$1"
}

check_container_running(){
  if ! "${DCMD[@]}" ps --status running | grep -q "$CONTAINER" 2>/dev/null; then
    err "Container '$CONTAINER' is not running (or not listed by compose file '$COMPOSE_FILE')."
    exit 3
  fi
}

# --- checks ---
check_container_running
info "Running read-only checks for \`App\\Services\\SignatoryService\` in container '$CONTAINER' (compose file: $COMPOSE_FILE)"

info "Checking file existence inside container..."
if run_in_container "test -f /var/www/siimut/app/Services/SignatoryService.php && echo 'FOUND' || echo 'MISSING'" | grep -q FOUND; then
  info "File exists: /var/www/siimut/app/Services/SignatoryService.php"
else
  warn "File NOT found at /var/www/siimut/app/Services/SignatoryService.php — check repository and mounts"
fi

info "Printing top of file (namespace + class header, first 60 lines):"
run_in_container "sed -n '1,60p' /var/www/siimut/app/Services/SignatoryService.php" || true

info "Testing composer autoload awareness (class_exists) — expected 'true' but you reported 'false':"
run_in_container "php -r \"require 'vendor/autoload.php'; var_export(class_exists('App\\\\Services\\\\SignatoryService'));\"" || true

info "Searching vendor/composer for references to SignatoryService (may be empty for PSR-4):"
run_in_container "grep -R --line-number 'SignatoryService' vendor/composer || true" || true

info "Listing bootstrap/cache (Laravel compiled caches that may affect discovery):"
run_in_container "ls -la bootstrap/cache || true" || true

info "Checking OPcache / PHP caching settings (shows opcache.enable & validate_timestamps):"
run_in_container "php -i | egrep -i 'opcache.enable|validate_timestamps' || true" || true

# --- optional quick fixes inside container ---
if [[ $FIX -eq 1 ]]; then
  info "--fix requested: regenerating autoload and clearing Laravel caches (changes are only inside the running container)"
  info "Running: composer dump-autoload -o"
  run_in_container "composer dump-autoload -o" || warn "composer dump-autoload failed or composer not present in image"

  info "Running: php artisan optimize:clear"
  run_in_container "php artisan optimize:clear" || warn "artisan optimize:clear failed"

  info "Re-testing class_exists after dump-autoload + cache clear:"
  run_in_container "php -r \"require 'vendor/autoload.php'; var_export(class_exists('App\\\\Services\\\\SignatoryService'));\"" || true

  info "If class_exists is now true, the issue was autoload/caching. NOTE: this fix is ephemeral for baked images. Commit & rebuild image for permanent fix."
fi

# --- optional rebuild/push ---
if [[ $REBUILD -eq 1 ]]; then
  info "--rebuild requested: will attempt to build & push a new image and restart container."
  read -r -p "Proceed with build & push (this may take time)? [y/N] " ans
  if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
    warn "Rebuild aborted by user."
    exit 0
  fi

  if [[ -x ./build-push-dev.sh ]]; then
    info "Found ./build-push-dev.sh — executing it"
    ./build-push-dev.sh || { err "build-push-dev.sh failed"; exit 4; }
  else
    info "No ./build-push-dev.sh — running compose build + up for $CONTAINER"
    "${DCMD[@]}" build --no-cache "$CONTAINER" || { err "docker compose build failed"; exit 5; }
    "${DCMD[@]}" up -d --no-deps "$CONTAINER" || { err "docker compose up failed"; exit 6; }
  fi

  info "Re-checking class_exists after rebuild/restart (give container some seconds to come up)"
  sleep 3
  run_in_container "php -r \"require 'vendor/autoload.php'; var_export(class_exists('App\\\\Services\\\\SignatoryService'));\"" || true
  info "If class still not found after rebuild, verify the file is included in the build context and not excluded by .dockerignore."
fi

cat <<EOF

Done — summary / next steps:
- If 'class_exists' is false but file exists: likely autoload / composer classmap not updated or file namespace mismatch.
- Temporary fix: use --fix to regenerate autoload and clear caches inside the running container.
- Permanent fix: commit code changes and run --rebuild (or use CI to build/push image); for dev workflow consider mounting source as a bind mount.

EOF

exit 0
