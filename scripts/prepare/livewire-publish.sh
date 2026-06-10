#!/bin/bash

###############################################################################
# Livewire Asset Publishing Logic
# 
# This should be included in all PHP app entrypoints (app-siimut, app-ikp, app-iam)
# Ensures Livewire assets are always available and properly symlinked
#
# Usage: source this file in your entrypoint, or call publish_livewire_assets
###############################################################################

# Function to publish and verify Livewire assets
publish_livewire_assets() {
    local APP_NAME="${1:-siimut}"
    local APP_PATH="/var/www/$APP_NAME"
    local MAX_RETRIES=3
    local RETRY_COUNT=0
    
    echo "📦 Livewire Asset Publishing Process"
    echo "======================================"
    
    # Validate app directory exists
    if [ ! -d "$APP_PATH" ]; then
        echo "❌ ERROR: App directory not found: $APP_PATH"
        return 1
    fi
    
    echo "🔍 Checking current state:"
    
    # Check if vendor/livewire exists (Composer installed it)
    if [ -d "$APP_PATH/vendor/livewire" ]; then
        echo "  ✅ vendor/livewire/ exists"
    else
        echo "  ❌ vendor/livewire/ NOT found (Composer install may have failed)"
        return 1
    fi
    
    # Check if public/vendor/livewire exists
    if [ -d "$APP_PATH/public/vendor/livewire" ]; then
        echo "  ✅ public/vendor/livewire/ exists"
        FILE_COUNT=$(find "$APP_PATH/public/vendor/livewire" -type f | wc -l)
        echo "     └─ Files: $FILE_COUNT"
    else
        echo "  ❌ public/vendor/livewire/ NOT found (will publish)"
    fi
    
    # Publish Livewire assets
    echo ""
    echo "📝 Publishing assets (attempt 1/$MAX_RETRIES)..."
    
    cd "$APP_PATH"
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        RETRY_COUNT=$((RETRY_COUNT + 1))
        
        if php artisan livewire:publish --assets 2>&1 | tee /tmp/livewire-publish-$APP_NAME.log; then
            echo "  ✅ Publish command succeeded"
            break
        else
            echo "  ⚠️ Publish attempt $RETRY_COUNT failed"
            
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                WAIT_TIME=$((RETRY_COUNT * 2))
                echo "     Waiting ${WAIT_TIME}s before retry..."
                sleep $WAIT_TIME
                echo "📝 Publishing assets (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."
            fi
        fi
    done
    
    # Verify assets were published
    echo ""
    echo "🔍 Verifying published assets:"
    
    if [ -d "$APP_PATH/public/vendor/livewire" ]; then
        FILE_COUNT=$(find "$APP_PATH/public/vendor/livewire" -type f | wc -l)
        echo "  ✅ public/vendor/livewire/ exists with $FILE_COUNT files"
        
        # Check for main JS file
        if [ -f "$APP_PATH/public/vendor/livewire/livewire.min.js" ]; then
            FILE_SIZE=$(stat -c%s "$APP_PATH/public/vendor/livewire/livewire.min.js" 2>/dev/null || echo "unknown")
            echo "     └─ livewire.min.js: $FILE_SIZE bytes"
        else
            echo "  ❌ livewire.min.js NOT found"
            return 1
        fi
    else
        echo "  ❌ public/vendor/livewire/ still NOT found after publish"
        
        # Debug output
        echo ""
        echo "📋 Debug info:"
        echo "   Contents of public/vendor/:"
        ls -1 "$APP_PATH/public/vendor/" 2>/dev/null | sed 's/^/     /'
        
        echo ""
        echo "   Publish log:"
        tail -20 /tmp/livewire-publish-$APP_NAME.log 2>/dev/null | sed 's/^/     /'
        
        return 1
    fi
    
    # Create symlink for compatibility
    echo ""
    echo "🔗 Setting up symlink:"
    
    if [ -L "$APP_PATH/public/livewire" ]; then
        CURRENT_TARGET=$(readlink "$APP_PATH/public/livewire")
        if [ "$CURRENT_TARGET" = "vendor/livewire" ]; then
            echo "  ✅ Symlink already correct: public/livewire -> vendor/livewire"
        else
            echo "  ⚠️ Symlink exists but points to: $CURRENT_TARGET"
            echo "     Fixing symlink..."
            rm -f "$APP_PATH/public/livewire"
            ln -s vendor/livewire "$APP_PATH/public/livewire"
            echo "  ✅ Symlink fixed"
        fi
    elif [ -d "$APP_PATH/public/livewire" ]; then
        echo "  ⚠️ public/livewire/ exists as directory (not symlink)"
        echo "     Removing and creating symlink..."
        rm -rf "$APP_PATH/public/livewire"
        ln -s vendor/livewire "$APP_PATH/public/livewire"
        echo "  ✅ Replaced with symlink"
    else
        echo "  📝 Creating symlink..."
        ln -s vendor/livewire "$APP_PATH/public/livewire"
        echo "  ✅ Symlink created: public/livewire -> vendor/livewire"
    fi
    
    echo ""
    echo "✅ Livewire Asset Publishing Complete!"
    echo "========================================"
    
    return 0
}

# Export function for use in entrypoints
export -f publish_livewire_assets
