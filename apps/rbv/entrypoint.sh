#!/bin/sh
set -e

echo "🚀 Starting ${APP_NAME:-App} (env: ${APP_ENV:-production})"

APP_ENV="${APP_ENV:-production}"
APP_WORKDIR="${APP_WORKDIR:-/var/www/rbv}"

echo "📁 Using APP_WORKDIR=${APP_WORKDIR}"
cd "${APP_WORKDIR}"

if [ ! -f artisan ]; then
    echo "❌ Laravel artisan not found in ${APP_WORKDIR}"
    exit 1
fi

# .env check — copy from example, then override with runtime env vars
if [ -f .env.example ]; then
    cp .env.example .env
elif [ ! -f .env ]; then
    : > .env
fi

set_env() {
    local key="$1" value="$2"
    if grep -q "^${key}=" .env 2>/dev/null; then
        sed -i "s~^${key}=.*~${key}=${value}~" .env
    else
        printf '%s=%s\n' "$key" "$value" >> .env
    fi
}

# Override with compose-provided env vars
for var in \
    APP_ENV APP_DEBUG APP_WORKDIR APP_URL \
    DB_HOST DB_USERNAME DB_PASSWORD DB_DATABASE \
    AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_BUCKET AWS_URL AWS_ENDPOINT; do
    eval "is_set=\${${var}+x}"
    if [ "$is_set" = "x" ]; then
        eval "val=\${$var}"
        set_env "$var" "$val"
    fi
done

# Ensure APP_KEY is set
APP_KEY_VALUE=$(grep -E '^APP_KEY=' .env | head -1 | cut -d'=' -f2- || true)
if [ -z "${APP_KEY_VALUE}" ]; then
    php artisan key:generate --force
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
