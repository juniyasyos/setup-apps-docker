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
