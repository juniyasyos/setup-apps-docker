#!/bin/sh
set -e

echo "🚀 Starting SIIMUT Application (Standalone Mode - No SSO)"

APP_ENV="${APP_ENV:-production}"
APP_WORKDIR="${APP_WORKDIR:-/var/www/siimut}"
PUBLIC_VOLUME="${PUBLIC_VOLUME:-/var/www/public-shared-siimut}"

echo "📁 APP_WORKDIR=${APP_WORKDIR}"
cd "${APP_WORKDIR}"

# Validate Laravel
if [ ! -f artisan ]; then
    echo "❌ Laravel artisan not found in ${APP_WORKDIR}"
    exit 1
fi

# Validate .env
if [ "$APP_ENV" = "production" ] && [ ! -f ".env" ]; then
    echo "❌ .env not found in production mode"
    exit 1
fi

# ⚠️ DO NOT RUN switch-auth-mode.sh for standalone mode
echo "ℹ️  Standalone mode: Skipping authentication mode switch (SSO disabled)"

# Copy public assets to shared volume for Nginx (only if PUBLIC_VOLUME is set and exists)
if [ -n "${PUBLIC_VOLUME}" ] && [ -d "${PUBLIC_VOLUME}" ]; then
    echo "📦 Syncing public assets to ${PUBLIC_VOLUME}..."
    
    # Create target directory if not exists
    mkdir -p "${PUBLIC_VOLUME}"
    
    # Rsync or cp (rsync lebih efficient untuk update)
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --delete "${APP_WORKDIR}/public/" "${PUBLIC_VOLUME}/"
        echo "✅ Public assets synced via rsync"
    else
        # Fallback to cp
        rm -rf "${PUBLIC_VOLUME:?}"/*
        cp -r "${APP_WORKDIR}/public/." "${PUBLIC_VOLUME}/"
        echo "✅ Public assets copied"
    fi
    
    # Set permissions for Nginx to read
    chmod -R 755 "${PUBLIC_VOLUME}"
else
    echo "ℹ️  PUBLIC_VOLUME not set or doesn't exist, skipping public sync"
fi

# Wait for database
echo "⏳ Waiting for database..."
php -r '
$host    = getenv("DB_HOST") ?: "database-service";
$port    = getenv("DB_PORT") ?: 3306;
$timeout = 60;
$start   = time();

while (true) {
    $fp = @fsockopen($host, $port, $errno, $errstr, 2);
    if ($fp) {
        fclose($fp);
        fwrite(STDOUT, "✅ Database connected: {$host}:{$port}\n");
        break;
    }
    if (time() - $start > $timeout) {
        fwrite(STDERR, "❌ Database timeout after {$timeout}s\n");
        exit(1);
    }
    fwrite(STDOUT, "… waiting for DB {$host}:{$port}\n");
    sleep(2);
}
'

# Fix permissions BEFORE cache warming (penting!)
echo "🔧 Setting up permissions..."
# ALWAYS run permission setup, tidak peduli folder sudah ada atau tidak
# (Ini penting untuk fix permission dari volume yang dimount dari run sebelumnya)
mkdir -p storage/framework/cache/data \
         storage/framework/sessions \
         storage/framework/views \
         storage/framework/testing \
         storage/logs \
         storage/app/public \
         bootstrap/cache

# Ensure Laravel log file exists and is writable (prevents "Permission denied" on first write)
touch storage/logs/laravel.log

# Clear stale cache files yang mungkin corrupt atau orphaned
echo "🧹 Cleaning stale cache files..."
rm -rf storage/framework/views/*.php 2>/dev/null || true
rm -rf storage/framework/cache/data/* 2>/dev/null || true
rm -rf bootstrap/cache/*.php 2>/dev/null || true

# Set ownership dan permission - CRITICAL FIX!
# Run TANPA if [ -d storage ] check agar selalu di-execute
echo "  Setting ownership to www:www..."
chown -R www:www storage bootstrap/cache 2>/dev/null || true
echo "  Setting write permissions..."
chmod -R ug+rwX storage bootstrap/cache 2>/dev/null || true
chmod 664 storage/logs/laravel.log 2>/dev/null || true

# Verify permissions were set correctly
if [ -d storage ] && [ ! -w storage/framework/cache ]; then
  echo "⚠️  WARNING: storage/framework/cache is still not writable after chmod!"
  echo "   Current ownership: $(ls -ld storage/framework/cache | awk '{print $3":"$4}')"
  echo "   Current permissions: $(ls -ld storage/framework/cache | awk '{print $1}')"
fi

echo "✅ Permissions set"

# Build Frontend Assets
echo "📦 Building frontend assets..."
if [ -f package.json ]; then
  echo "  📋 Running npm install..."
  npm install --no-save 2>&1 | tail -5
  
  echo "  🔨 Running npm run build..."
  npm run build 2>&1 | tail -10
  
  echo "✅ Frontend build complete"
else
  echo "⚠️  package.json not found, skipping npm build"
fi

# Laravel cache warming (run as www user)
echo "⚙️  Warming Laravel caches..."

# Clear all caches first to prevent stale/corrupted cache issues
echo "🧹 Clearing all caches..."
su-exec www php artisan cache:clear    >/dev/null 2>&1 || true
su-exec www php artisan config:clear   >/dev/null 2>&1 || true
su-exec www php artisan route:clear    >/dev/null 2>&1 || true
su-exec www php artisan view:clear     >/dev/null 2>&1 || true
su-exec www php artisan event:clear    >/dev/null 2>&1 || true

# Rebuild caches
echo "♻️  Rebuilding caches..."
su-exec www php artisan config:cache   >/dev/null 2>&1 || echo "⚠️ config:cache failed"
su-exec www php artisan route:cache    >/dev/null 2>&1 || echo "⚠️ route:cache failed"
su-exec www php artisan view:cache     >/dev/null 2>&1 || echo "⚠️ view:cache failed"
su-exec www php artisan event:cache    >/dev/null 2>&1 || echo "⚠️ event:cache failed"

# Run artisan optimize
echo "⚡ Running artisan optimize..."
su-exec www php artisan optimize       >/dev/null 2>&1 || echo "⚠️ artisan optimize failed"

# Verify critical directories are writable
echo "🔍 Verifying cache directories..."
for dir in storage/framework/views storage/framework/cache bootstrap/cache; do
  if [ -d "$dir" ] && [ ! -w "$dir" ]; then
    echo "⚠️ Warning: $dir is not writable"
  fi
done

echo "✅ SIIMUT App ready at: $(date)"

# Execute main command
if [ $# -eq 0 ]; then
    set -- php-fpm -F
fi

echo "🚀 Starting: $*"
exec "$@"
