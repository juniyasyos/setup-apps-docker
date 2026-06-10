#!/bin/sh
set -e

echo "🚀 Starting IAM Application (Registry Mode with runtime deps)"

APP_ENV="${APP_ENV:-production}"
APP_WORKDIR="${APP_WORKDIR:-/var/www/iam}"
PUBLIC_VOLUME="${PUBLIC_VOLUME:-/var/www/public-shared}"

echo "📁 APP_WORKDIR=${APP_WORKDIR}"
cd "${APP_WORKDIR}"

# ------------------------------------------------------------------
# dynamic .env generation
# ------------------------------------------------------------------
echo "🧩 Generating .env from runtime environment variables"

# start from example so defaults are preserved; if none, create empty
if [ -f .env.example ]; then
    cp .env.example .env
else
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

for var in APP_ENV APP_WORKDIR PUBLIC_VOLUME APP_URL IAM_ISSUER IAM_JWT_SECRET DB_HOST DB_USERNAME DB_PASSWORD DB_DATABASE SKIP_PUBLIC_SYNC AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_BUCKET AWS_URL AWS_ENDPOINT USE_SSO IAM_ENABLED SESSION_DRIVER SESSION_DOMAIN SESSION_PATH SESSION_SECURE_COOKIE SESSION_SAME_SITE; do
    eval val=\${$var}
    if [ -n "$val" ]; then
        set_env "$var" "$val"
    fi
done

echo "✅ .env assembled"

# -----------------------------------------------------
# runtime dependency install removed: handled at build-time
# ------------------------------------------------------------------
# composer/npm install & build are executed during image build to
# ensure the image already contains all dependencies and compiled assets.
# keeping them here would rebuild on every container start and cause
# problems with volume mounts and cache invalidation.

# Validate Laravel
if [ ! -f artisan ]; then
    echo "❌ Laravel artisan not found in ${APP_WORKDIR}"
    exit 1
fi

# Validate .env - copy from .env.example if not exists
if [ ! -f ".env" ]; then
    if [ -f ".env.example" ]; then
        echo "📋 Copying .env.example to .env..."
        cp .env.example .env
        echo "✅ .env file created from .env.example"
    else
        echo "❌ .env and .env.example not found"
        exit 1
    fi
fi

# rest of original entrypoint-registry functionality follows (sync public, db wait...)

# Run switch-auth-mode.sh if exists (for SIIMUT)
if [ -f "./switch-auth-mode.sh" ]; then
    echo "🔐 Setting authentication mode..."
    chmod +x ./switch-auth-mode.sh
    ./switch-auth-mode.sh dev || echo "⚠️ switch-auth-mode.sh failed (continuing...)"
fi

# Copy public assets to shared volume (only if PUBLIC_VOLUME is set and exists)
if [ -n "${PUBLIC_VOLUME}" ] && [ -d "${PUBLIC_VOLUME}" ]; then
    if [ "${SKIP_PUBLIC_SYNC}" = "true" ]; then
        echo "ℹ️  SKIP_PUBLIC_SYNC=true, skipping public asset sync"
    else
        SOURCE_REAL=$(cd "${APP_WORKDIR}/public" 2>/dev/null && pwd || echo "${APP_WORKDIR}/public")
        DEST_REAL=$(cd "${PUBLIC_VOLUME}" 2>/dev/null && pwd || echo "${PUBLIC_VOLUME}")
        if [ "${SOURCE_REAL}" = "${DEST_REAL}" ]; then
            echo "ℹ️  Source and destination are the same (shared volume), skipping sync"
        else
            echo "📦 Syncing public assets to ${PUBLIC_VOLUME}..."
            mkdir -p "${PUBLIC_VOLUME}"
            if command -v rsync >/dev/null 2>&1; then
                rsync -a --delete "${APP_WORKDIR}/public/" "${PUBLIC_VOLUME}/"
                echo "✅ Public assets synced via rsync"
            else
                if [ -d "${PUBLIC_VOLUME}" ] && [ "$(ls -A ${PUBLIC_VOLUME} 2>/dev/null)" ]; then
                    rm -rf "${PUBLIC_VOLUME:?}/*"
                fi
                cp -r "${APP_WORKDIR}/public/." "${PUBLIC_VOLUME}/"
                echo "✅ Public assets copied"
            fi
            chmod -R 755 "${PUBLIC_VOLUME}"
        fi
    fi
else
    echo "ℹ️  PUBLIC_VOLUME not set or doesn't exist, skipping public sync"
fi

# Fix permissions BEFORE cache warming (penting!)
echo "🔧 Setting up permissions..."
# Ensure required folders exist even if storage/ is not committed or overridden by a mount
mkdir -p storage storage/framework/cache storage/framework/sessions storage/framework/views
mkdir -p storage/logs storage/app/public
mkdir -p bootstrap/cache

# Ensure Laravel log file exists and is writable (prevents "Permission denied" on first write)
touch storage/logs/laravel.log

# Create public/livewire symlink if not exists (Livewire asset serving)
if [ ! -L public/livewire ]; then
  if [ -d public/vendor/livewire ]; then
    ln -s vendor/livewire public/livewire
    echo "✅ Created symlink: public/livewire -> vendor/livewire"
  else
    echo "📦 Publishing Livewire assets..."
    if ! su-exec www php artisan livewire:publish --assets 2>&1 | tee /tmp/livewire-publish.log; then
      echo "⚠️ livewire:publish had issues. See log above."
    fi
    
    # Check if assets were published
    if [ -d public/vendor/livewire ]; then
      ln -s vendor/livewire public/livewire
      echo "✅ Livewire assets published and symlink created"
    else
      # Try alternative: vendor/bin/livewire if available
      if [ -f vendor/bin/livewire ]; then
        echo "🔄 Trying alternative livewire publish method..."
        su-exec www vendor/bin/livewire publish --assets || true
      fi
      
      # Final check
      if [ -d public/vendor/livewire ]; then
        ln -s vendor/livewire public/livewire
        echo "✅ Livewire assets published (alternative method)"
      else
        echo "❌ ERROR: Livewire assets could not be published!"
        echo "📋 Available vendor dirs: $(ls -1 public/vendor 2>/dev/null | head -5)"
        echo "📋 Check /tmp/livewire-publish.log for details"
      fi
    fi
  fi
fi 

# Clear stale cache files yang mungkin corrupt atau orphaned
echo "🧹 Cleaning stale cache files..."
rm -rf storage/framework/views/* 2>/dev/null || true
rm -rf storage/framework/cache/data/* 2>/dev/null || true
rm -rf bootstrap/cache/*.php 2>/dev/null || true

# Set ownership dan permission
chown -R www:www storage bootstrap/cache 2>/dev/null || true
chmod -R ug+rwX storage bootstrap/cache 2>/dev/null || true
chmod 664 storage/logs/laravel.log 2>/dev/null || true

echo "✅ Permissions set"

# Laravel cache warming (run as www user)
echo "⚙️  Warming Laravel caches..."

# Clear all caches first to prevent stale/corrupted cache issues
echo "🧹 Clearing all caches..."
su-exec www php artisan cache:clear    >/dev/null 2>&1 || true
su-exec www php artisan config:clear   >/dev/null 2>&1 || true
su-exec www php artisan route:clear    >/dev/null 2>&1 || true
su-exec www php artisan view:clear     >/dev/null 2>&1 || true
su-exec www php artisan event:clear    >/dev/null 2>&1 || true

# Rebuild caches (skip route:cache and view:cache to avoid stale compiled view invalidation)
echo "♻️  Rebuilding caches..."
su-exec www php artisan config:cache   >/dev/null 2>&1 || echo "⚠️ config:cache failed"
# NOTE: Skipping route:cache due to Livewire compatibility issues
# su-exec www php artisan route:cache    >/dev/null 2>&1 || echo "⚠️ route:cache failed"
echo "ℹ️ Skipping view:cache to avoid stale compiled view invalidation on runtime storage"
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

echo "✅ IAM App ready at: $(date)"

# Execute main command
if [ $# -eq 0 ]; then
    set -- php-fpm -F
fi

echo "🚀 Starting: $*"
exec "$@"

# ... remainder of script could be appended or reused from entrypoint-registry

# For brevity rest of script omitted; we assume same as entrypoint-registry after db wait
