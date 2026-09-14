#!/usr/bin/env bash
# =============================================================================
# RSCH Platform — Master Full Backup & Extraction Runner
# =============================================================================
# Menjalankan seluruh proses ekstraksi secara berurutan:
#   1. Ekstraksi seluruh database MySQL (backup-mysql.sh)
#   2. Ekstraksi seluruh bucket & file MinIO (backup-minio.sh)
#   3. Backup volume persistent storage aplikasi Laravel (uploads/storage)
#   4. Backup file konfigurasi environment (.env)
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
STORAGE_BACKUP_DIR="${SCRIPT_DIR}/backup_data/storage_volumes/${TIMESTAMP}"
ENV_BACKUP_DIR="${SCRIPT_DIR}/backup_data/environments/${TIMESTAMP}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     RSCH PLATFORM — FULL SYSTEM DATA EXTRACTION RUNNER      ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo -e "Waktu Mulai: $(date)"
echo ""

# 1. Ekstraksi MySQL Database
echo -e "${BOLD}${BLUE}==> [1/4] Menjalankan Ekstraksi Database MySQL...${NC}"
"${SCRIPT_DIR}/backup-mysql.sh"

# 2. Ekstraksi MinIO S3 Object Storage
echo -e "${BOLD}${BLUE}==> [2/4] Menjalankan Ekstraksi MinIO S3 Storage...${NC}"
"${SCRIPT_DIR}/backup-minio.sh"

# 3. Ekstraksi Volume Persistent Laravel Storage
echo -e "\n${BOLD}${BLUE}==> [3/4] Menjalankan Ekstraksi Volume Laravel Storage (Uploads/Dokumen)...${NC}"
mkdir -p "$STORAGE_BACKUP_DIR"

VOLUMES=$(docker volume ls -q | grep -E 'storage' || echo "")
if [ -n "$VOLUMES" ]; then
    for vol in $VOLUMES; do
        echo -e "  • Mengarsipkan volume: ${BOLD}${vol}${NC}..."
        docker run --rm \
            -v "${vol}":/source:ro \
            -v "${STORAGE_BACKUP_DIR}":/backup \
            alpine tar -czf "/backup/${vol}.tar.gz" -C /source .
    done
    echo -e "${GREEN}✅ Semua volume persistent storage berhasil diarsipkan di: ${STORAGE_BACKUP_DIR}${NC}"
else
    echo -e "${YELLOW}⚠️  Tidak ada Docker volume storage yang ditemukan saat ini.${NC}"
fi

# 4. Backup Konfigurasi Envs
echo -e "\n${BOLD}${BLUE}==> [4/4] Mengamankan File Konfigurasi (.env)...${NC}"
mkdir -p "$ENV_BACKUP_DIR"
cp -a "${SCRIPT_DIR}"/.env* "${ENV_BACKUP_DIR}/" 2>/dev/null || true
if [ -d "${SCRIPT_DIR}/env" ]; then
    cp -r "${SCRIPT_DIR}/env" "${ENV_BACKUP_DIR}/" 2>/dev/null || true
fi
echo -e "${GREEN}✅ File konfigurasi environment berhasil diamankan di: ${ENV_BACKUP_DIR}${NC}"

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}🎉 SELURUH DATA SISTEM TELAH BERHASIL DIEKSTRAK DENGAN AMAN!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}"
echo -e "Folder Utama Hasil Backup:"
echo -e "  📂 ${BOLD}${SCRIPT_DIR}/backup_data/${NC}"
echo -e "     ├── mysql/latest/"
echo -e "     ├── minio/latest/"
echo -e "     ├── storage_volumes/${TIMESTAMP}/"
echo -e "     └── environments/${TIMESTAMP}/"
echo -e "${GREEN}══════════════════════════════════════════════════════════════${NC}\n"
