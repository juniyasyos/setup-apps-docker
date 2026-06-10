#!/bin/sh
set -e

echo "🚀 Starting Apps (env: ${APP_ENV:-production})"

APP_ENV="${APP_ENV:-production}"
APP_WORKDIR="${APP_WORKDIR:-/var/www/html}"  # 🔹 default, bisa dioverride dari Docker/compose

echo "📁 Using APP_WORKDIR=${APP_WORKDIR}"

cd "${APP_WORKDIR}"

# Pastikan Laravel ada
if [ ! -f artisan ]; then
    echo "❌ Laravel artisan file not found in ${APP_WORKDIR}"
    exit 1
fi

# Cek .env
if [ "$APP_ENV" = "production" ]; then
    echo "🏭 Production mode - .env must exist"
    if [ ! -f ".env" ]; then
        echo "❌ .env not found in production mode. Please provide .env (env_file / mount)."
        exit 1
    fi
else
    echo "⚠️ Non-production environment: $APP_ENV"
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            echo "⚙️ .env not found, creating from .env.example..."
            cp .env.example .env
        else
            echo "❌ No .env or .env.example found."
            exit 1
        fi
    fi
fi

# Tunggu DB siap (optional tapi helpful)
echo "⏳ Waiting for database connection..."

php -r '
$host    = getenv("DB_HOST") ?: "db";
$port    = getenv("DB_PORT") ?: 3306;
$timeout = 60;
$start   = time();

while (true) {
    $fp = @fsockopen($host, $port, $errno, $errstr, 2);
    if ($fp) {
        fclose($fp);
        fwrite(STDOUT, "✅ Database connection established to {$host}:{$port}\n");
        break;
    }
    if (time() - $start > $timeout) {
        fwrite(STDERR, "❌ Database connection timeout after {$timeout}s ({$host}:{$port})\n");
        exit(1);
    }
    fwrite(STDOUT, "… waiting for database {$host}:{$port}\n");
    sleep(2);
}
';

# INFO Redis
echo "ℹ️  Redis disabled - using DB for cache/session/queue"

# Warm up cache (tidak bikin container mati kalau gagal)
echo "⚙️  Warming up Laravel caches..."

php artisan config:cache   >/dev/null 2>&1 || echo "⚠️ config:cache failed (continuing...)"
php artisan route:cache    >/dev/null 2>&1 || echo "⚠️ route:cache failed (continuing...)"
php artisan view:cache     >/dev/null 2>&1 || echo "⚠️ view:cache failed (continuing...)"
php artisan event:cache    >/dev/null 2>&1 || echo "⚠️ event:cache failed (continuing...)"

# Publish Livewire assets if needed
echo "📦 Checking Livewire assets..."
if [ ! -d "public/vendor/livewire" ]; then
    echo "🔄 Publishing Livewire assets..."
    php artisan livewire:publish --assets || echo "⚠️ livewire:publish failed"
    if [ -d "public/vendor/livewire" ] && [ ! -L "public/livewire" ]; then
        ln -s vendor/livewire public/livewire
        echo "✅ Livewire symlink created"
    fi
else
    echo "✅ Livewire assets already present"
    if [ ! -L "public/livewire" ]; then
        ln -s vendor/livewire public/livewire
    fi
fi

echo "📊 Container ready at: $(date)"

# Fix permissions for storage & cache (relatif ke APP_WORKDIR)
if [ -d storage ]; then
  chown -R www:www storage bootstrap/cache || true
  chmod -R ug+rwX storage bootstrap/cache || true
fi

# Kalau tidak ada command yang dikasih dari Dockerfile/compose, pakai php-fpm -F
if [ $# -eq 0 ]; then
    set -- php-fpm -F
fi

echo "🚀 Starting main process: $*"

exec "$@"
