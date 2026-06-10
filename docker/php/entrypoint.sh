#!/bin/sh
set -eo pipefail

echo "🚀 Starting App (Production Registry Mode)"

APP_ENV="${APP_ENV:-production}"
APP_WORKDIR="${APP_WORKDIR:-/var/www/siimut}"
PUBLIC_VOLUME="${PUBLIC_VOLUME:-/var/www/public-shared}"

echo "📁 APP_WORKDIR=${APP_WORKDIR}"
cd "${APP_WORKDIR}"

# ------------------------------------------------------------------
# dynamic .env generation
# build a fresh .env from whatever environment variables are present
# this lets us push the same image and configure everything at runtime
# ------------------------------------------------------------------
echo "🧩 Generating .env from runtime environment variables"

# start from example so defaults are preserved; if none, create empty
if [ -f .env.example ]; then
    cp .env.example .env
else
    : > .env
fi

# helper that inserts or replaces a key in the file
set_env() {
    local key="$1" value="$2"
    if grep -q "^${key}=" .env 2>/dev/null; then
        sed -i "s~^${key}=.*~${key}=${value}~" .env
    else
        # Ensure trailing newline before appending to avoid corrupting last line
        # (e.g., VITE_APP_NAME="${APP_NAME}"APP_WORKDIR=/var/www/lms-app)
        if [ -s .env ] && [ "$(tail -c1 .env | xxd -p)" != "0a" ]; then
            echo >> .env
        fi
        printf '%s=%s\n' "$key" "$value" >> .env
    fi
}

# helper for running commands as the www user when available
run_as_www() {
    if command -v su-exec >/dev/null 2>&1; then
        su-exec www "$@"
    elif command -v gosu >/dev/null 2>&1; then
        gosu www "$@"
    elif [ "$(id -u)" = "0" ] && command -v su >/dev/null 2>&1; then
        su -s /bin/sh www -c "$(printf '%s ' "$@")"
    else
        "$@"
    fi
}

# list of variables we care about (add more as needed)
for var in \
    APP_ENV APP_WORKDIR PUBLIC_VOLUME APP_URL \
    DB_HOST DB_USERNAME DB_PASSWORD DB_DATABASE \
    SKIP_PUBLIC_SYNC \
    AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_BUCKET AWS_URL AWS_ENDPOINT \
    USE_SSO IAM_ENABLED IAM_HOST IAM_BASE_URL IAM_ISSUER \
    IAM_VERIFY_ENDPOINT IAM_REFRESH_TOKEN_ENDPOINT IAM_BACKCHANNEL_USER_APPLICATIONS_ENDPOINT \
    IAM_APP_KEY IAM_JWT_SECRET IAM_LOGIN_ROUTE IAM_LOGIN_ROUTE_NAME \
    IAM_CALLBACK_ROUTE IAM_CALLBACK_FULL_URL IAM_DEFAULT_REDIRECT \
    IAM_GUARD IAM_USER_MODEL IAM_IDENTIFIER_FIELD IAM_PRESERVE_SESSION_ID \
    IAM_SYNC_ROLES IAM_ROLE_GUARD_NAME IAM_STORE_TOKEN_IN_SESSION \
    IAM_ROLE_SYNC_MODE IAM_ROLE_SYNC_FROM_IAM_ALLOW_CREATE SSO_SECRET \
    IAM_BACKCHANNEL_METHOD IAM_BACKCHANNEL_VERIFY IAM_USER_APPLICATIONS_ENDPOINT \
    IAM_VERIFY_EACH_REQUEST IAM_VERIFY_REMOTE_EACH_REQUEST IAM_ATTACH_VERIFY_MIDDLEWARE \
    IAM_SYNC_SESSION_LIFETIME IAM_SESSION_LIFETIME_BUFFER \
    LOG_CHANNEL LOG_STACK \
    SESSION_DRIVER SESSION_DOMAIN SESSION_PATH SESSION_SECURE_COOKIE SESSION_SAME_SITE SESSION_HTTPONLY; do
    # Write variable to .env when it exists in runtime env, including empty values (e.g. SESSION_DOMAIN=)
    eval "is_set=\${${var}+x}"
    if [ "$is_set" = "x" ]; then
        eval "val=\${$var}"
        set_env "$var" "$val"
    fi
done

echo "✅ .env assembled"

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

# Ensure APP_KEY is set (generate if missing/empty)
APP_KEY_VALUE=$(grep -E '^APP_KEY=' .env | head -1 | cut -d'=' -f2- || true)
if [ -z "${APP_KEY_VALUE}" ]; then
    echo "🔐 Generating APP_KEY..."
    php artisan key:generate --force
fi

# Run switch-auth-mode.sh if exists (for SIIMUT)
if [ -f "./switch-auth-mode.sh" ]; then
    if [ "${USE_SSO}" = "true" ] || [ "${IAM_ENABLED}" = "true" ]; then
        echo "ℹ️ SSO enabled, skipping switch-auth-mode.sh to preserve runtime IAM/session configuration"
    else
        echo "🔐 Setting authentication mode..."
        chmod +x ./switch-auth-mode.sh
        AUTH_MODE="dev"
        if [ "${APP_ENV}" = "production" ]; then
            AUTH_MODE="prod"
        fi
        echo "ℹ️ Selected auth mode: ${AUTH_MODE} (USE_SSO=${USE_SSO:-}, IAM_ENABLED=${IAM_ENABLED:-}, APP_ENV=${APP_ENV:-})"
        ./switch-auth-mode.sh "${AUTH_MODE}" || echo "⚠️ switch-auth-mode.sh failed (continuing...)"
    fi
fi

# Copy public assets to shared volume (only if PUBLIC_VOLUME is set and exists)
# Skip if SKIP_PUBLIC_SYNC is true or if source and destination are the same
if [ -n "${PUBLIC_VOLUME}" ] && [ -d "${PUBLIC_VOLUME}" ]; then
    
    # Check if we should skip sync
    if [ "${SKIP_PUBLIC_SYNC}" = "true" ]; then
        echo "ℹ️  SKIP_PUBLIC_SYNC=true, skipping public asset sync"
    else
        # Check if source and destination are the same
        SOURCE_REAL=$(cd "${APP_WORKDIR}/public" 2>/dev/null && pwd || echo "${APP_WORKDIR}/public")
        DEST_REAL=$(cd "${PUBLIC_VOLUME}" 2>/dev/null && pwd || echo "${PUBLIC_VOLUME}")
        
        if [ "${SOURCE_REAL}" = "${DEST_REAL}" ]; then
            echo "ℹ️  Source and destination are the same (shared volume), skipping sync"
        else
            echo "📦 Syncing public assets to ${PUBLIC_VOLUME}..."
            
            # Create target directory if not exists
            mkdir -p "${PUBLIC_VOLUME}"
            
            # Rsync or cp (rsync lebih efficient untuk update)
            if command -v rsync >/dev/null 2>&1; then
              # Run sync as www to avoid root-owned files in mounted volume
              run_as_www rsync -a --delete "${APP_WORKDIR}/public/" "${PUBLIC_VOLUME}/" && 
                echo "✅ Public assets synced via rsync" || echo "⚠️ rsync failed"
            else
              # Fallback to cp (run as www)
              if [ -d "${PUBLIC_VOLUME}" ] && [ "$(ls -A ${PUBLIC_VOLUME} 2>/dev/null)" ]; then
                rm -rf "${PUBLIC_VOLUME:?}"/*
              fi
              run_as_www cp -r "${APP_WORKDIR}/public/." "${PUBLIC_VOLUME}/" && 
                echo "✅ Public assets copied" || echo "⚠️ cp failed"
            fi
            
            # Set permissions for Caddy to read (ensure owned by www)
            chown -R www:www "${PUBLIC_VOLUME}" 2>/dev/null || true
            chmod -R 755 "${PUBLIC_VOLUME}" 2>/dev/null || true
        fi
    fi
else
    echo "ℹ️  PUBLIC_VOLUME not set or doesn't exist, skipping public sync"
fi

# Fix permissions BEFORE cache warming (penting!)
echo "🔧 Setting up permissions..."
mkdir -p storage/framework/cache/data \
         storage/framework/sessions \
         storage/framework/views \
         storage/framework/testing \
         storage/logs \
         storage/app/public \
         bootstrap/cache

# Ensure Laravel log file exists and is writable (prevents "Permission denied" on first write)
touch storage/logs/laravel.log

# Remove stale bootstrap cache from previous builds that may reference dev-only providers
echo "🧹 Clearing stale bootstrap cache files..."
rm -f bootstrap/cache/services.php bootstrap/cache/packages.php bootstrap/cache/config.php bootstrap/cache/routes-v7.php bootstrap/cache/events.php bootstrap/cache/modules.php bootstrap/cache/settings.php 2>/dev/null || true

# Publish and verify Livewire assets (CRITICAL - do this BEFORE symlink)
echo "📦 Ensuring Livewire assets are published..."

LIVEWIRE_MAX_RETRIES=3
LIVEWIRE_RETRY_COUNT=0
LIVEWIRE_PUBLISHED=0

while [ $LIVEWIRE_RETRY_COUNT -lt $LIVEWIRE_MAX_RETRIES ] && [ $LIVEWIRE_PUBLISHED -eq 0 ]; do
  LIVEWIRE_RETRY_COUNT=$((LIVEWIRE_RETRY_COUNT + 1))
  
  # Check if assets already exist
  if [ -d public/vendor/livewire ] && [ -f public/vendor/livewire/livewire.min.js ]; then
    echo "✅ Livewire assets already present"
    LIVEWIRE_PUBLISHED=1
    break
  fi
  
  # Attempt to publish
  echo "  🔄 Attempt $LIVEWIRE_RETRY_COUNT/$LIVEWIRE_MAX_RETRIES: Running livewire:publish..."
  if run_as_www php artisan livewire:publish --assets 2>&1 | tee /tmp/livewire-publish.log; then
    echo "  ✓ Publish command succeeded"
  else
    echo "  ⚠️ Publish command had exit code > 0"
  fi
  
  # Verify assets exist after publish attempt
  if [ -d public/vendor/livewire ] && [ -f public/vendor/livewire/livewire.min.js ]; then
    echo "  ✅ Livewire assets verified at public/vendor/livewire/"
    LIVEWIRE_PUBLISHED=1
    break
  elif [ -d public/vendor/livewire ]; then
    echo "  ⚠️ Directory exists but livewire.min.js missing. Contents:"
    ls -la public/vendor/livewire/ | head -5
  else
    echo "  ❌ public/vendor/livewire directory not found"
    
    # Debug: show what's in public/vendor/
    if [ -d public/vendor ]; then
      echo "  📋 Available in public/vendor: $(ls -1 public/vendor/ 2>/dev/null | tr '\n' ' ')"
    else
      echo "  📋 public/vendor directory does not exist"
    fi
    
    # Try alternative method
    if [ $LIVEWIRE_RETRY_COUNT -eq 1 ] && [ -f vendor/bin/livewire ]; then
      echo "  🔄 Trying vendor/bin/livewire (alternative)..."
      run_as_www vendor/bin/livewire publish --assets 2>&1 || echo "  ⚠️ Alternative method also failed"
    fi
  fi
  
  # Wait before retry
  if [ $LIVEWIRE_RETRY_COUNT -lt $LIVEWIRE_MAX_RETRIES ] && [ $LIVEWIRE_PUBLISHED -eq 0 ]; then
    echo "  ⏳ Waiting 2 seconds before retry..."
    sleep 2
  fi
done

# Create symlink (only if assets are actually present)
if [ -d public/vendor/livewire ]; then
  if [ ! -L public/livewire ]; then
    rm -f public/livewire  # Remove if it's a regular directory
    ln -s vendor/livewire public/livewire
    echo "✅ Created symlink: public/livewire -> vendor/livewire"
  else
    echo "✅ Symlink public/livewire -> vendor/livewire already exists"
  fi
else
  echo "❌ CRITICAL: Livewire assets could not be published after $LIVEWIRE_MAX_RETRIES attempts!"
  echo "📋 Check /tmp/livewire-publish.log for details"
  echo "This will cause Livewire 404 errors in the application!"
  # Don't exit - let app start anyway, but log the issue
fi
  
  # Clear stale cache files yang mungkin corrupt atau orphaned
echo "🧹 Cleaning stale cache files..."
rm -rf storage/framework/views/* 2>/dev/null || true
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
if [ ! -w storage/framework/cache ]; then
  echo "⚠️  WARNING: storage/framework/cache is still not writable after chmod!"
  echo "   Current ownership: $(ls -ld storage/framework/cache | awk '{print $3":"$4}')"
  echo "   Current permissions: $(ls -ld storage/framework/cache | awk '{print $1}')"
fi

echo "✅ Permissions set"

# Laravel cache warming (run as www user)
echo "⚙️  Warming Laravel caches..."

# Clear all caches first to prevent stale/corrupted cache issues
echo "🧹 Clearing all caches..."
run_as_www php artisan cache:clear    >/dev/null 2>&1 || true
run_as_www php artisan config:clear   >/dev/null 2>&1 || true
run_as_www php artisan route:clear    >/dev/null 2>&1 || true
run_as_www php artisan view:clear     >/dev/null 2>&1 || true
run_as_www php artisan event:clear    >/dev/null 2>&1 || true

# Discover packages (was skipped at build time with --no-scripts)
echo "🔍 Running package:discover..."
run_as_www php artisan package:discover --ansi 2>&1 || echo "⚠️ package:discover failed"

# Rebuild caches (skip route:cache and view:cache to avoid stale compiled view invalidation)
echo "♻️  Rebuilding caches..."
run_as_www php artisan config:cache   >/dev/null 2>&1 || echo "⚠️ config:cache failed"
# NOTE: Skipping route:cache due to Livewire compatibility issues
# run_as_www php artisan route:cache    >/dev/null 2>&1 || echo "⚠️ route:cache failed"
echo "ℹ️ Skipping view:cache to avoid stale compiled view invalidation on runtime storage"
run_as_www php artisan event:cache    >/dev/null 2>&1 || echo "⚠️ event:cache failed"

# Run artisan optimize
echo "⚡ Running artisan optimize..."
run_as_www php artisan optimize       >/dev/null 2>&1 || echo "⚠️ artisan optimize failed"

# Verify critical directories are writable
echo "🔍 Verifying cache directories..."
for dir in storage/framework/views storage/framework/cache bootstrap/cache; do
  if [ -d "$dir" ] && [ ! -w "$dir" ]; then
    echo "⚠️ Warning: $dir is not writable"
  fi
done

echo "✅ IAM App ready at: $(date)"

# show minio configuration so we can inspect at runtime
echo "🌐 Minio endpoint (AWS_ENDPOINT)=${AWS_ENDPOINT:-<unset>}"
echo "🌐 Minio bucket (AWS_BUCKET)=${AWS_BUCKET:-<unset>}"

# check port numbers extracted from AWS_ENDPOINT
if [ -n "${AWS_ENDPOINT}" ]; then
    port=$(echo "$AWS_ENDPOINT" | awk -F: '{print $NF}')
    echo "🔢 Minio endpoint port detected: $port"
    if [ "$port" != "9090" ]; then
        echo "⚠️  unexpected port for AWS_ENDPOINT (expected 9090)"
    fi
fi

# optionally show the console port separately (9091)
echo "🔐 Minio console is usually at port 9091 (not used by app)"

# attempt simple connectivity test (requires curl in image)
echo "🔗 Testing connectivity to Minio..."
if command -v curl >/dev/null 2>&1; then
    if curl -fsS --max-time 5 "${AWS_ENDPOINT:-}" >/dev/null 2>&1; then
        echo "✅ Able to reach Minio at ${AWS_ENDPOINT:-}"
    else
        echo "❌ Cannot reach Minio at ${AWS_ENDPOINT:-} (curl failed)"
    fi
else
    echo "⚠️  curl not available; skipping network check"
fi


# Execute main command
if [ $# -eq 0 ]; then
    set -- php-fpm -F
fi

echo "🚀 Starting: $*"
exec "$@"
