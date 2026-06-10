#!/bin/bash

# Script untuk memeriksa apakah JWT secrets sama di semua service
# Services: app-siimut, app-ikp, app-iam

# Dapatkan base directory (direktori tempat script berada)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_DIR="${SCRIPT_DIR}/env"

echo "=== JWT SECRET VERIFICATION ==="
echo "Script directory: $SCRIPT_DIR"
echo "Env directory: $ENV_DIR"
echo ""

# Function untuk mendapatkan JWT secret dari container
get_jwt_secret() {
    local service=$1
    docker exec $service sh -c 'echo $IAM_JWT_SECRET' 2>/dev/null
}

# Function untuk mendapatkan nilai dari env file
get_jwt_from_env() {
    local env_file=$1
    grep "^IAM_JWT_SECRET=" "$env_file" | cut -d'=' -f2
}

# Function untuk menemukan env file
find_env_file() {
    local service=$1
    local app_name="${service#app-}"
    local env_file="$ENV_DIR/.env.$app_name"
    
    if [ -f "$env_file" ]; then
        echo "$env_file"
    else
        echo ""
    fi
}

# Array untuk menyimpan hasil
declare -A secrets
declare -a services=("app-siimut" "app-ikp" "app-iam")

# Check setiap service
for service in "${services[@]}"; do
    echo "Checking $service..."
    
    # Coba ambil dari container yang running
    secret=$(get_jwt_secret "$service")
    
    # Jika container tidak running atau env kosong, ambil dari env file
    if [ -z "$secret" ]; then
        env_file=$(find_env_file "$service")
        if [ -n "$env_file" ] && [ -f "$env_file" ]; then
            secret=$(get_jwt_from_env "$env_file")
            echo "  (dari file: $env_file)"
        else
            secret="NOT_FOUND"
            echo "  ❌ File tidak ditemukan"
        fi
    else
        echo "  (dari container)"
    fi
    
    secrets[$service]="$secret"
    echo "  Value: ${secret:0:20}... (truncated)"
    echo ""
done

# Verifikasi kesamaan
echo "=== VERIFICATION RESULT ==="
echo ""

all_same=true
first_secret="${secrets[app-siimut]}"

for service in "${services[@]}"; do
    if [ "${secrets[$service]}" != "$first_secret" ]; then
        all_same=false
        break
    fi
done

if [ "$all_same" = true ] && [ "$first_secret" != "NOT_FOUND" ]; then
    echo "✅ BAGUS! Semua JWT secrets SAMA di ketiga service"
    echo ""
    echo "Details:"
    for service in "${services[@]}"; do
        echo "  $service: ${secrets[$service]}"
    done
else
    echo "❌ BERMASALAH! JWT secrets TIDAK SAMA atau tidak ditemukan"
    echo ""
    echo "Details:"
    for service in "${services[@]}"; do
        echo "  $service: ${secrets[$service]}"
    done
fi

echo ""
echo "=== END OF VERIFICATION ==="
