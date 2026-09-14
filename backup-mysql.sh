#!/usr/bin/env bash
# =============================================================================
# RSCH Platform — Automated MySQL Full Database Extraction Script
# =============================================================================
# Skrip ini mengekstrak SELURUH basis data MySQL yang ada di dalam kontainer.
# Fitur:
#   1. Deteksi otomatis kontainer MySQL & kredensial root.
#   2. Audit metadata (daftar tabel dan jumlah baris) sebelum backup.
#   3. Full monolithic dump (seluruh database dalam satu file).
#   4. Individual database dump (per aplikasi: siimut, ikp, iam, dll).
#   5. Kompresi gzip dan pembuatan checksum SHA256 untuk verifikasi integritas.
#   6. Tersimpan rapi di: ./backup_data/mysql/<timestamp>/
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${SCRIPT_DIR}/backup_data/mysql/${TIMESTAMP}"

# ANSI Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warn()    { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error()   { echo -e "${RED}❌ $1${NC}"; }
log_step()    { echo -e "\n${CYAN}══════════════════════════════════════════════════════════════${NC}"; echo -e "${BOLD}${CYAN}   $1${NC}"; echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}"; }

# ─────────────────────────────────────────────────────────────────────────────
# TAHAP 1: Deteksi Kontainer & Kredensial MySQL
# ─────────────────────────────────────────────────────────────────────────────
log_step "TAHAP 1: Pemeriksaan Kontainer & Kredensial MySQL"

# 1. Deteksi Nama Kontainer
DB_CONTAINER=""
if docker ps --format '{{.Names}}' | grep -q "^database-service$"; then
    DB_CONTAINER="database-service"
elif docker ps --format '{{.Names}}' | grep -q "database"; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep "database" | head -n 1)
elif docker ps --format '{{.Names}}' | grep -q "mysql"; then
    DB_CONTAINER=$(docker ps --format '{{.Names}}' | grep "mysql" | head -n 1)
fi

if [ -z "$DB_CONTAINER" ]; then
    log_error "Kontainer MySQL tidak ditemukan atau sedang TIDAK BERJALAN!"
    echo ""
    log_warn "Pastikan kontainer database aktif terlebih dahulu:"
    echo "  docker compose -f docker-compose.base.yml up -d db"
    echo "  (atau: ./rsch infra up db)"
    exit 1
fi
log_success "Kontainer MySQL terdeteksi: ${BOLD}${DB_CONTAINER}${NC}"

# 2. Uji Koneksi ke MySQL (Root Tanpa Password)
if ! docker exec "$DB_CONTAINER" mysql -u root -e "SELECT 1;" >/dev/null 2>&1; then
    log_error "Gagal login ke MySQL dengan user root tanpa password pada kontainer ${DB_CONTAINER}!"
    log_warn "Pastikan kontainer database aktif dan user root diizinkan masuk tanpa password."
    exit 1
fi
log_success "Koneksi ke MySQL database berhasil (root tanpa password)."

# ─────────────────────────────────────────────────────────────────────────────
# TAHAP 2: Audit & Inventarisasi Database
# ─────────────────────────────────────────────────────────────────────────────
log_step "TAHAP 2: Audit & Inventarisasi Seluruh Basis Data"

mkdir -p "${OUTPUT_DIR}/individual"
mkdir -p "${OUTPUT_DIR}/metadata"

# Ambil daftar seluruh database (abaikan sistem database default MySQL)
EXCLUDED_DB="'information_schema', 'mysql', 'performance_schema', 'sys'"
QUERY_GET_DBS="SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN (${EXCLUDED_DB}) ORDER BY schema_name;"

DATABASES=$(docker exec -i "$DB_CONTAINER" mysql -u root -s -N -e "${QUERY_GET_DBS}")

if [ -z "$DATABASES" ]; then
    log_warn "Tidak ditemukan database aplikasi tambahan (hanya sistem MySQL default)!"
else
    echo -e "Daftar database yang akan diekstrak:"
    for db in $DATABASES; do
        echo -e "  • ${BOLD}${db}${NC}"
    done
fi

echo "$DATABASES" > "${OUTPUT_DIR}/metadata/databases_list.txt"

# Simpan metadata struktur & jumlah baris tabel untuk verifikasi
log_info "Merekam baseline metadata tabel dan perkiraan baris..."
QUERY_AUDIT="
SELECT 
    table_schema AS 'Database',
    COUNT(table_name) AS 'Total_Tables',
    ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size_MB'
FROM information_schema.tables 
WHERE table_schema NOT IN (${EXCLUDED_DB})
GROUP BY table_schema;
"
docker exec -i "$DB_CONTAINER" mysql -u root -t -e "${QUERY_AUDIT}" > "${OUTPUT_DIR}/metadata/baseline_table_summary.txt"
cat "${OUTPUT_DIR}/metadata/baseline_table_summary.txt"

# ─────────────────────────────────────────────────────────────────────────────
# TAHAP 3: Ekstraksi Monolithic (Full Dump Semua Database)
# ─────────────────────────────────────────────────────────────────────────────
log_step "TAHAP 3: Membuat Full Dump Monolitik (All Databases)"

FULL_DUMP_FILE="${OUTPUT_DIR}/all_databases_${TIMESTAMP}.sql"
log_info "Mengekspor seluruh database ke: ${FULL_DUMP_FILE} ..."

docker exec -i "$DB_CONTAINER" mysqldump -u root \
    --all-databases \
    --single-transaction \
    --quick \
    --routines \
    --triggers \
    --events \
    --hex-blob \
    --max-allowed-packet=512M \
    --default-character-set=utf8mb4 > "$FULL_DUMP_FILE"

FULL_SIZE=$(du -h "$FULL_DUMP_FILE" | cut -f1)
log_success "Full dump berhasil dibuat! Ukuran: ${BOLD}${FULL_SIZE}${NC}"

# Kompres salinan full dump dengan gzip
log_info "Mengompresi salinan full dump (gzip)..."
gzip -c "$FULL_DUMP_FILE" > "${FULL_DUMP_FILE}.gz"
GZ_SIZE=$(du -h "${FULL_DUMP_FILE}.gz" | cut -f1)
log_success "Arsip terkompresi selesai: ${FULL_DUMP_FILE}.gz (${GZ_SIZE})"

# ─────────────────────────────────────────────────────────────────────────────
# TAHAP 4: Ekstraksi Individual per Database
# ─────────────────────────────────────────────────────────────────────────────
log_step "TAHAP 4: Mengekstrak File SQL Terpisah per Aplikasi"

for db in $DATABASES; do
    log_info "Mengekspor database: ${BOLD}${db}${NC}..."
    DB_FILE="${OUTPUT_DIR}/individual/${db}.sql"
    
    docker exec -i "$DB_CONTAINER" mysqldump -u root \
        --databases "$db" \
        --single-transaction \
        --quick \
        --routines \
        --triggers \
        --events \
        --hex-blob \
        --max-allowed-packet=512M \
        --default-character-set=utf8mb4 > "$DB_FILE"
    
    # Checksum SHA256 untuk memvalidasi isi file nantinya
    sha256sum "$DB_FILE" > "${DB_FILE}.sha256"
    
    # Kompresi per DB
    gzip -c "$DB_FILE" > "${DB_FILE}.gz"
    
    FILE_SIZE=$(du -h "$DB_FILE" | cut -f1)
    log_success "Selesai: ${db}.sql (${FILE_SIZE})"
done

# ─────────────────────────────────────────────────────────────────────────────
# TAHAP 5: Ringkasan & Link Cepat
# ─────────────────────────────────────────────────────────────────────────────
log_step "TAHAP 5: Selesai & Ringkasan Ekstraksi"

# Buat pointer symlink ke backup terbaru
LATEST_LINK="${SCRIPT_DIR}/backup_data/mysql/latest"
rm -f "$LATEST_LINK"
ln -s "$TIMESTAMP" "$LATEST_LINK"

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${BOLD}${GREEN}   ✅ EKSTRAKSI DATABASE MYSQL SELESAI DENGAN SUKSES!${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "📁 Lokasi Penyimpanan : ${BOLD}${OUTPUT_DIR}${NC}"
echo -e "🔗 Symlink Shortcut   : ${BOLD}${LATEST_LINK}${NC}"
echo ""
echo -e "Struktur Hasil Ekstraksi:"
echo -e "  ├── ${BOLD}all_databases_${TIMESTAMP}.sql${NC}       (Dump keseluruhan)"
echo -e "  ├── ${BOLD}all_databases_${TIMESTAMP}.sql.gz${NC}    (Arsip kompresi)"
echo -e "  ├── ${BOLD}individual/${NC}                       (Dump per database: siimut, ikp, dll)"
echo -e "  └── ${BOLD}metadata/${NC}                         (Daftar database & jumlah tabel)"
echo ""
log_info "Tips restore database tertentu di lingkungan baru:"
echo -e "  ${YELLOW}mysql -u root -p < ${OUTPUT_DIR}/individual/<nama_db>.sql${NC}"
echo -e "${GREEN}================================================================${NC}\n"
