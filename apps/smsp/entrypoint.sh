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
