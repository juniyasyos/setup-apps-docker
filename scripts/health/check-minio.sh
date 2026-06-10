#!/bin/bash

set -u

COMPOSE_FILE="docker-compose-multi-apps.yml"
MINIO_HEALTH_PATH="/minio/health/ready"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

services=(
  "app-siimut|siimut|siimut"
  "app-ikp|ikp|ikp"
  "app-iam|iam-server|data-center"
)

if ! docker compose -f "$COMPOSE_FILE" ps >/dev/null 2>&1; then
  echo "❌ Tidak bisa menjalankan docker compose dengan file $COMPOSE_FILE"
  exit 1
fi

echo "=================================="
echo "MINIO CONNECTION CHECK"
echo "=================================="
echo "Timestamp: $(date)"
echo "Compose file: $COMPOSE_FILE"
echo ""

overall_failed=0

for entry in "${services[@]}"; do
  IFS='|' read -r service app_label expected_bucket <<< "$entry"

  echo -e "${YELLOW}=== ${app_label} (${service}) ===${NC}"

  if ! docker compose -f "$COMPOSE_FILE" ps "$service" >/dev/null 2>&1; then
    echo -e "${RED}❌ Service $service tidak ditemukan atau compose gagal membaca statusnya${NC}"
    overall_failed=1
    echo ""
    continue
  fi

  endpoint=$(docker compose -f "$COMPOSE_FILE" exec -T "$service" sh -lc 'printf "%s" "${AWS_ENDPOINT:-}"' 2>/dev/null || true)
  bucket=$(docker compose -f "$COMPOSE_FILE" exec -T "$service" sh -lc 'printf "%s" "${AWS_BUCKET:-}"' 2>/dev/null || true)
  use_path_style=$(docker compose -f "$COMPOSE_FILE" exec -T "$service" sh -lc 'printf "%s" "${AWS_USE_PATH_STYLE_ENDPOINT:-}"' 2>/dev/null || true)

  echo "AWS_ENDPOINT: ${endpoint:-<unset>}"
  echo "AWS_BUCKET: ${bucket:-<unset>}"
  echo "AWS_USE_PATH_STYLE_ENDPOINT: ${use_path_style:-<unset>}"

  if [ -z "${endpoint:-}" ]; then
    echo -e "${RED}❌ $app_label gagal: AWS_ENDPOINT belum disetel${NC}"
    overall_failed=1
    echo ""
    continue
  fi

  if [ -n "$expected_bucket" ] && [ -n "${bucket:-}" ] && [ "$bucket" != "$expected_bucket" ]; then
    echo -e "${YELLOW}⚠️  Bucket app tidak sama dengan nilai yang diharapkan: $bucket (expected: $expected_bucket)${NC}"
  fi

  if docker compose -f "$COMPOSE_FILE" exec -T "$service" sh -lc "curl -fsS --max-time 5 '${endpoint}${MINIO_HEALTH_PATH}' >/dev/null" >/dev/null 2>&1; then
    echo -e "${GREEN}✅ $app_label bisa menjangkau MinIO di $endpoint${NC}"
  else
    echo -e "${RED}❌ $app_label tidak bisa menjangkau MinIO di $endpoint${NC}"
    overall_failed=1
  fi

  echo ""
done

if [ "$overall_failed" -eq 0 ]; then
  echo -e "${GREEN}=== HASIL: SEMUA APP TERHUBUNG KE MINIO ===${NC}"
else
  echo -e "${RED}=== HASIL: ADA APP YANG BELUM TERHUBUNG KE MINIO ===${NC}"
fi

exit "$overall_failed"