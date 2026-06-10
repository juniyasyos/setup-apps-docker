#!/usr/bin/env bash
# diagnose-autoload.sh
# Scan PHP classes under the app directory inside the running `app-siimut` container,
# check whether Composer autoload recognizes them (class_exists), detect path/namespace
# mismatches, and optionally apply temporary fixes (composer dump-autoload + optimize:clear)
# or trigger image rebuild.

set -o errexit
set -o pipefail
set -o nounset

COMPOSE_FILE="./docker-compose-multi-apps.yml"
CONTAINER="app-siimut"
TARGET_DIR="/var/www/siimut/app"
FIX=0
REBUILD=0
REPORT_FILE=""
ONLY_MISSING=0

usage(){
  cat <<EOF
Usage: $0 [options]
Options:
  --fix                 Regenerate autoload & clear Laravel caches inside container (ephemeral)
  --rebuild             Build & push image (runs ./build-push-dev.sh when present) and restart container
  --report <file>       Save JSONL report to <file>
  --only-missing        Show only classes that class_exists() reports false
  -f <compose-file>     Docker compose file (default: ${COMPOSE_FILE})
  -c <container>        Container name (default: ${CONTAINER})
  -p <path>             Path inside container to scan (default: ${TARGET_DIR})
  -h, --help            Show this help

Examples:
  $0                    # scan and show results
  $0 --only-missing     # show only missing classes
  $0 --fix               # attempt temporary fix (dump-autoload + clear caches)
  $0 --report out.jsonl  # save full JSONL report
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix) FIX=1; shift ;;
    --rebuild) REBUILD=1; shift ;;
    --report) REPORT_FILE="$2"; shift 2 ;;
    --only-missing) ONLY_MISSING=1; shift ;;
    -f) COMPOSE_FILE="$2"; shift 2 ;;
    -c) CONTAINER="$2"; shift 2 ;;
    -p) TARGET_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 2 ;;
  esac
done

DCMD=(docker compose -f "$COMPOSE_FILE")

run_in_container(){
  "${DCMD[@]}" exec -T "$CONTAINER" bash -lc "$1"
}

check_container_running(){
  if ! "${DCMD[@]}" ps --status running | grep -q "$CONTAINER" 2>/dev/null; then
    echo "[ERROR] Container '$CONTAINER' is not running or not defined in $COMPOSE_FILE" >&2
    exit 3
  fi
}

check_container_running

info(){ printf "[INFO] %s\n" "$*"; }
warn(){ printf "[WARN] %s\n" "$*"; }
err(){ printf "[ERROR] %s\n" "$*"; }

# Create and run a PHP helper inside the container to enumerate classes and test autoload
generate_report_in_container(){
  # create helper *inside* the container and execute it there (previously it was written on the host)
  run_in_container "cat > /tmp/diagnose_autoload_helper.php <<'PHP'
<?php
$dir = getenv('DIAG_DIR') ?: '/var/www/siimut/app';
$rii = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($dir));
foreach ($rii as $file) {
    if (!$file->isFile()) continue;
    if (pathinfo($file->getFilename(), PATHINFO_EXTENSION) !== 'php') continue;
    $src = file_get_contents($file->getRealPath());
    $tokens = token_get_all($src);
    $namespace = '';
    $found = false;
    for ($i = 0, $c = count($tokens); $i < $c; $i++) {
        $t = $tokens[$i];
        if (!is_array($t)) continue;
        if ($t[0] === T_NAMESPACE) {
            $i++;
            $ns = '';
            while (isset($tokens[$i]) && (is_array($tokens[$i]) && ($tokens[$i][0] === T_STRING || $tokens[$i][0] === T_NS_SEPARATOR))) {
                $ns .= $tokens[$i][1]; $i++;
            }
            $namespace = $ns;
        }
        if ($t[0] === T_CLASS || $t[0] === T_INTERFACE || $t[0] === T_TRAIT) {
            // skip anonymous classes (next token may be T_WHITESPACE then '(' )
            $j = $i + 1;
            while (isset($tokens[$j]) && is_array($tokens[$j]) && $tokens[$j][0] === T_WHITESPACE) $j++;
            if (!isset($tokens[$j]) || !is_array($tokens[$j]) || $tokens[$j][0] !== T_STRING) continue;
            $class = $tokens[$j][1];
            $fqcn = ($namespace ? $namespace . '\\' : '') . $class;
            $exists = class_exists($fqcn) || interface_exists($fqcn) || trait_exists($fqcn);
            $expected = null; $psr4_ok = null; $path_mismatch = false;
            if (strpos($fqcn, 'App\\') === 0) {
                $rel = substr($fqcn, 4);
                $expected = '/var/www/siimut/' . str_replace('\\\\', '/', $rel) . '.php';
                $expected = str_replace('\\', '/', $expected);
                $expected_real = is_file($expected) ? realpath($expected) : null;
                $actual_real = realpath($file->getRealPath());
                $psr4_ok = ($expected_real && $actual_real && $expected_real === $actual_real);
                if (!$psr4_ok) $path_mismatch = true;
            }
            $status = $exists ? 'OK' : 'MISSING_AUTOLOAD';
            if ($path_mismatch) $status = 'PATH_MISMATCH';
            echo json_encode([
                'status' => $status,
                'fqcn' => $fqcn,
                'file' => $file->getRealPath(),
                'expected' => $expected,
                'autoload_recognizes' => $exists,
            ]) . PHP_EOL;
            $found = true;
        }
    }
    // optional: files without declared class are ignored
}
PHP
DIAG_DIR=${TARGET_DIR} php /tmp/diagnose_autoload_helper.php; rm -f /tmp/diagnose_autoload_helper.php"
}

# Run scan and capture output
info "Scanning PHP classes under '$TARGET_DIR' inside container '$CONTAINER'..."
OUT=$(generate_report_in_container)

if [[ -z "$OUT" ]]; then
  warn "No classes found under $TARGET_DIR or the PHP helper failed to run. Check path and container state."
  exit 0
fi

# Optionally save raw JSONL
if [[ -n "$REPORT_FILE" ]]; then
  printf "%s\n" "$OUT" > "$REPORT_FILE"
  info "Saved full JSONL report to $REPORT_FILE"
fi

# Summarize
TOTAL=$(printf "%s\n" "$OUT" | wc -l)
OK=$(printf "%s\n" "$OUT" | grep -c '"status":"OK"' || true)
MISSING=$(printf "%s\n" "$OUT" | grep -c '"MISSING_AUTOLOAD"' || true)
PATH_MISMATCH=$(printf "%s\n" "$OUT" | grep -c '"PATH_MISMATCH"' || true)

info "Scan results: total=$TOTAL, ok=$OK, missing_autoload=$MISSING, path_mismatch=$PATH_MISMATCH"

# Show details (only-missing option filters)
if [[ $ONLY_MISSING -eq 1 ]]; then
  printf "%s\n" "$OUT" | grep -E 'MISSING_AUTOLOAD|PATH_MISMATCH' || true
else
  printf "%s\n" "$OUT" | sed -n '1,200p'
fi

# If user requested a temporary fix inside container
if [[ $FIX -eq 1 ]]; then
  info "--fix requested: regenerating composer autoload and clearing Laravel caches inside the container (ephemeral)"
  run_in_container "composer dump-autoload -o || true"
  run_in_container "php artisan optimize:clear || true"
  info "Re-running scan after fix..."
  OUT2=$(generate_report_in_container)
  TOTAL2=$(printf "%s\n" "$OUT2" | wc -l)
  OK2=$(printf "%s\n" "$OUT2" | grep -c '"status":"OK"' || true)
  MISSING2=$(printf "%s\n" "$OUT2" | grep -c '"MISSING_AUTOLOAD"' || true)
  info "After fix: total=$TOTAL2, ok=$OK2, missing_autoload=$MISSING2"
  printf "%s\n" "$OUT2" | grep -E 'MISSING_AUTOLOAD|PATH_MISMATCH' || true
fi

# Optional rebuild/push
if [[ $REBUILD -eq 1 ]]; then
  info "--rebuild requested: will attempt to build & push a new image and restart container."
  read -r -p "Proceed with build & push (this may take time)? [y/N] " ans
  if [[ "$ans" != "y" && "$ans" != "Y" ]]; then
    warn "Rebuild aborted by user."
    exit 0
  fi
  if [[ -x ./build-push-dev.sh ]]; then
    info "Executing ./build-push-dev.sh"
    ./build-push-dev.sh || { err "build-push-dev.sh failed"; exit 4; }
  else
    info "Running compose build + up for $CONTAINER"
    "${DCMD[@]}" build --no-cache "$CONTAINER" || { err "docker compose build failed"; exit 5; }
    "${DCMD[@]}" up -d --no-deps "$CONTAINER" || { err "docker compose up failed"; exit 6; }
  fi
  info "Re-checking after rebuild (give container a few seconds to come up)"
  sleep 3
  generate_report_in_container
fi

cat <<EOF

Summary / next steps:
- 'MISSING_AUTOLOAD' means Composer autoload doesn't know the class (run --fix or rebuild image).
- 'PATH_MISMATCH' indicates PSR-4 path/namespace not matching file path (fix namespace or move/rename file).
- For permanent deploys, commit changes and build/push the image; for dev, consider bind-mounting source into container.

EOF

exit 0
