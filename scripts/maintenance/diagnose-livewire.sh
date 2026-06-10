#!/bin/bash

###############################################################################
# Server Livewire 404 - Quick Diagnosis & Recovery Script
# 
# Use this script to quickly diagnose and fix Livewire 404 issues 
# on production server with docker-compose-multi-apps.yml
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DOCKER_COMPOSE_FILE="${1:-docker-compose-multi-apps.yml}"
COMPOSE_CMD="docker compose"

echo -e "${BLUE}======================================"
echo "🔍 Livewire 404 - Server Diagnosis Tool"
echo "======================================${NC}\n"

# Check if compose file exists
if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
    echo -e "${RED}❌ ERROR: File not found: $DOCKER_COMPOSE_FILE${NC}"
    echo "   Current directory: $(pwd)"
    echo "   Please run from directory containing docker-compose-multi-apps.yml"
    exit 1
fi

# Try to detect docker compose command (newer vs older)
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ ERROR: docker not found in PATH${NC}"
    exit 1
fi

if ! $COMPOSE_CMD version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
    if ! $COMPOSE_CMD version &>/dev/null 2>&1; then
        echo -e "${RED}❌ ERROR: Neither 'docker compose' nor 'docker-compose' found${NC}"
        exit 1
    fi
fi

echo -e "${YELLOW}Using docker command:${NC} $COMPOSE_CMD"
echo -e "${YELLOW}Compose file:${NC} $DOCKER_COMPOSE_FILE\n"

# Show currently running containers first
echo -e "${BLUE}📋 Currently running containers:${NC}"
$COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" ps 2>/dev/null | grep -E "siimut|ikp|iam|web" || echo "  (none found or error)"
echo ""

# Detect app containers from compose file (app, queue, scheduler)
APP_CONTAINERS=$(grep "container_name:" "$DOCKER_COMPOSE_FILE" | grep -E "app-|queue-|scheduler-" | sed 's/.*container_name: //' | sed 's/\${[^}]*}/multi/g' | sort -u)

echo -e "${YELLOW}Detected containers from compose file:${NC}"
echo "$APP_CONTAINERS" | sed 's/^/  /'
echo ""

# Function to check single container
check_app() {
    local CONTAINER=$1
    
    # Extract container type and app name from container name
    # app-siimut -> app, siimut
    # queue-siimut -> queue, siimut
    # scheduler-siimut -> scheduler, siimut
    local CONTAINER_TYPE=$(echo "$CONTAINER" | cut -d'-' -f1)
    local APP_NAME=$(echo "$CONTAINER" | cut -d'-' -f2-)
    local APP_PATH="/var/www/$APP_NAME"
    
    echo -e "\n${BLUE}═══ Checking: $CONTAINER (type: $CONTAINER_TYPE, app: $APP_NAME) ═══${NC}"
    
    # 1. Check if container exists and is running
    # Try to get container status
    local STATUS=$($COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" ps "$CONTAINER" 2>/dev/null | grep "$CONTAINER" | awk '{print $(NF-1)}' || echo "ERROR")
    
    if [ "$STATUS" = "ERROR" ] || ! $COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" ps "$CONTAINER" 2>/dev/null | grep -q "$CONTAINER"; then
        echo -e "${RED}  ❌ Container not found or not running: $CONTAINER${NC}"
        echo -e "${YELLOW}     Hint: Container might be named differently or not started${NC}"
        return 1
    fi
    
    if echo "$STATUS" | grep -q "Up"; then
        echo -e "${GREEN}  ✅ Container is running (Status: $STATUS)${NC}"
    else
        echo -e "${RED}  ❌ Container not running (Status: $STATUS)${NC}"
        return 1
    fi
    
    # Only check Livewire for app containers (not queue or scheduler)
    if [ "$CONTAINER_TYPE" != "app" ]; then
        echo -e "${YELLOW}  ℹ️  Skipping Livewire check for $CONTAINER_TYPE container${NC}"
        return 0
    fi
    
    # 2. Check Livewire folder
    if $COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" exec -T "$CONTAINER" test -d "${APP_PATH}/public/vendor/livewire" 2>/dev/null; then
        echo -e "${GREEN}  ✅ Folder exists: public/vendor/livewire/${NC}"
        
        # 3. Check main file
        if $COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" exec -T "$CONTAINER" test -f "${APP_PATH}/public/vendor/livewire/livewire.min.js" 2>/dev/null; then
            FILE_SIZE=$($COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" exec -T "$CONTAINER" stat -c%s "${APP_PATH}/public/vendor/livewire/livewire.min.js" 2>/dev/null || echo "unknown")
            echo -e "${GREEN}  ✅ File exists: livewire.min.js ($FILE_SIZE bytes)${NC}"
        else
            echo -e "${RED}  ❌ File missing: livewire.min.js${NC}"
        fi
        
        # 4. Check symlink
        if $COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" exec -T "$CONTAINER" test -L "${APP_PATH}/public/livewire" 2>/dev/null; then
            TARGET=$($COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" exec -T "$CONTAINER" readlink "${APP_PATH}/public/livewire" 2>/dev/null)
            echo -e "${GREEN}  ✅ Symlink exists: public/livewire -> $TARGET${NC}"
        else
            echo -e "${YELLOW}  ⚠️  Symlink missing (but folder might still work)${NC}"
        fi
    else
        echo -e "${RED}  ❌ Folder NOT FOUND: public/vendor/livewire/${NC}"
        
        # Debug
        echo -e "${YELLOW}  📋 Contents of public/vendor/:${NC}"
        $COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" exec -T "$CONTAINER" sh -c "ls -1 ${APP_PATH}/public/vendor/ 2>/dev/null || echo '(directory empty or not found)'" | sed 's/^/    /'
        
        return 1
    fi
    
    return 0
}

# Function to fix app
fix_app() {
    local CONTAINER=$1
    
    # Extract container type and app name from container name
    # app-siimut -> app, siimut
    local CONTAINER_TYPE=$(echo "$CONTAINER" | cut -d'-' -f1)
    local APP_NAME=$(echo "$CONTAINER" | cut -d'-' -f2-)
    local APP_PATH="/var/www/$APP_NAME"
    
    # Only fix app containers (not queue or scheduler)
    if [ "$CONTAINER_TYPE" != "app" ]; then
        return 0
    fi
    
    echo -e "\n${BLUE}🔧 Attempting to fix: $CONTAINER${NC}"
    
    # Run publish command
    echo -e "  📦 Running livewire:publish..."
    if $COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" exec -T "$CONTAINER" sh -c "cd ${APP_PATH} && php artisan livewire:publish --assets" 2>&1 | tail -3; then
        echo -e "${GREEN}  ✓ Publish command completed${NC}"
    else
        echo -e "${YELLOW}  ⚠️ Publish command had issues${NC}"
    fi
    
    # Verify
    echo -e "  🔍 Verifying..."
    check_app "$CONTAINER"
}

# Main menu
show_menu() {
    echo -e "\n${BLUE}Select action:${NC}"
    echo "  1) Diagnose all apps"
    echo "  2) Diagnose and attempt fix (if broken)"
    echo "  3) Force fix all apps"
    echo "  4) Show detailed logs for an app"
    echo "  5) Exit"
    echo -n "Choice [1-5]: "
}

# Main loop
while true; do
    show_menu
    read choice
    
    case $choice in
        1)
            echo -e "\n${BLUE}📊 Running diagnosis...${NC}"
            ALL_OK=true
            for CONTAINER in $APP_CONTAINERS; do
                if ! check_app "$CONTAINER"; then
                    ALL_OK=false
                fi
            done
            
            if [ "$ALL_OK" = "true" ]; then
                echo -e "\n${GREEN}✅ All apps OK!${NC}"
            else
                echo -e "\n${RED}⚠️  Some issues found${NC}"
            fi
            ;;
        
        2)
            echo -e "\n${BLUE}🔧 Running diagnosis with auto-fix...${NC}"
            for CONTAINER in $APP_CONTAINERS; do
                if ! check_app "$CONTAINER"; then
                    fix_app "$CONTAINER"
                fi
            done
            ;;
        
        3)
            echo -e "\n${YELLOW}⚠️  Force fixing all app containers...${NC}"
            for CONTAINER in $APP_CONTAINERS; do
                CONTAINER_TYPE=$(echo "$CONTAINER" | cut -d'-' -f1)
                if [ "$CONTAINER_TYPE" = "app" ]; then
                    fix_app "$CONTAINER"
                fi
            done
            ;;
        
        4)
            echo -n "Container name [e.g., app-siimut, app-ikp, app-iam]: "
            read container_name
            echo -e "\n${BLUE}📋 Entrypoint logs for $container_name (last 50 lines):${NC}"
            $COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" logs "$container_name" --tail=50 2>/dev/null | grep -E "Livewire|vendor|publish|📦|✅|❌" || echo "No Livewire-related logs found"
            
            echo -e "\n${BLUE}📋 Publish log (if exists):${NC}"
            $COMPOSE_CMD -f "$DOCKER_COMPOSE_FILE" exec -T "$container_name" cat /tmp/livewire-publish.log 2>/dev/null || echo "Log not found"
            ;;
        
        5)
            echo -e "\n${GREEN}Goodbye!${NC}"
            exit 0
            ;;
        
        *)
            echo -e "${RED}❌ Invalid choice${NC}"
            ;;
    esac
done
