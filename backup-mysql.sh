#!/usr/bin/env bash
# =============================================================================
# RSCH Platform — Automated MySQL App Database Extraction Script
# =============================================================================
# Skrip ini mengekstrak SELURUH basis data aplikasi MySQL menggunakan 
# kredensial pengguna aplikasi terkonfigurasi (TANPA MENGGUNAKAN USER ROOT).
# Fitur:
#   1. Akses kontainer MySQL via Docker Compose (service: db / container: database-core).
#   2. Penggunaan kredensial terisolasi per-aplikasi (siimut_user, ikp_user, iam_user, dll).
#   3. Audit metadata tabel dan baris per basis data.
#   4. Individual database dump per aplikasi.
#   5. Combined monolithic dump (seluruh database aplikasi dalam satu file).
#   6. Kompresi gzip dan pembuatan checksum SHA256 untuk verifikasi integritas.
#   7. Tersimpan rapi di: ./backup_data/mysql/<timestamp>/
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
# TAHAP 1: Deteksi Kontainer via Docker Compose & Verifikasi User Aplikasi
# ─────────────────────────────────────────────────────────────────────────────
log_step "TAHAP 1: Pemeriksaan Kontainer & Kredensial User Aplikasi (Tanpa Root)"

# 1. Deteksi Metode Akses (Docker Compose / Docker Exec)
COMPOSE_CMD=()
if [ -f "${SCRIPT_DIR}/compose/base/database.yml" ] && docker compose -f "${SCRIPT_DIR}/compose/base/database.yml" ps --services 2>/dev/null | grep -q "^db$"; then
    COMPOSE_CMD=(docker compose -f "${SCRIPT_DIR}/compose/base/database.yml" exec -T db)
    log_success "Mengakses kontainer MySQL via Docker Compose: ${BOLD}compose/base/database.yml (service: db)${NC}"
elif [ -f "${SCRIPT_DIR}/compose/base/infra.yml" ] && docker compose -f "${SCRIPT_DIR}/compose/base/infra.yml" ps --services 2>/dev/null | grep -q "^db$"; then
    COMPOSE_CMD=(docker compose -f "${SCRIPT_DIR}/compose/base/infra.yml" exec -T db)
    log_success "Mengakses kontainer MySQL via Docker Compose: ${BOLD}compose/base/infra.yml (service: db)${NC}"
elif [ -f "${SCRIPT_DIR}/compose.yml" ] && docker compose -f "${SCRIPT_DIR}/compose.yml" ps --services 2>/dev/null | grep -q "^db$"; then
    COMPOSE_CMD=(docker compose -f "${SCRIPT_DIR}/compose.yml" exec -T db)
    log_success "Mengakses kontainer MySQL via Docker Compose: ${BOLD}compose.yml (service: db)${NC}"
elif [ -f "${SCRIPT_DIR}/docker-compose.base.yml" ] && docker compose -f "${SCRIPT_DIR}/docker-compose.base.yml" ps --services 2>/dev/null | grep -q "^db$"; then
    COMPOSE_CMD=(docker compose -f "${SCRIPT_DIR}/docker-compose.base.yml" exec -T db)
    log_success "Mengakses kontainer MySQL via Docker Compose: ${BOLD}docker-compose.base.yml (service: db)${NC}"
elif docker ps --format '{{.Names}}' | grep -q "^database-core$"; then
    COMPOSE_CMD=(docker exec -i database-core)
    log_success "Mengakses kontainer MySQL via Docker Exec: ${BOLD}database-core${NC}"
elif docker ps --format '{{.Names}}' | grep -q "^database-service$"; then
    COMPOSE_CMD=(docker exec -i database-service)
    log_success "Mengakses kontainer MySQL via Docker Exec: ${BOLD}database-service${NC}"
else
    log_error "Kontainer MySQL (service 'db') tidak ditemukan atau sedang TIDAK BERJALAN!"
    echo ""
    log_warn "Pastikan kontainer database aktif terlebih dahulu:"
    echo "  ./rsch storage up"
    echo "  (atau: docker compose -f compose/base/infra.yml up -d db)"
    exit 1
fi

# 2. Peta Kredensial Aplikasi (Default & Ekstraksi Dinamis dari file env)
declare -A APP_DBS=(
    ["siimut_db"]="siimut_user:siimut-password"
    ["ikp_db"]="ikp_user:ikp-password"
    ["iam_db"]="iam_user:iam-password"
    ["lms_db"]="lms_user:lms-password"
    ["rbv_db"]="rbv_user:rbv-password"
    ["smsp_db"]="smsp_user:smsp-password"
    ["template1_db"]="template1_user:template1_password"
)

# Pindai file .env di folder env/ dan apps/*/ untuk menemukan database aplikasi tambahan
for env_file in "${SCRIPT_DIR}"/env/.env.* "${SCRIPT_DIR}"/env/*.env "${SCRIPT_DIR}"/apps/*/.env* "${SCRIPT_DIR}"/.env*; do
    [ -f "$env_file" ] || continue
    db_name=$(grep -E '^(DB_DATABASE|MYSQL_DATABASE)=' "$env_file" | head -n 1 | cut -d'=' -f2- | tr -d '\r"' || echo "")
    db_user=$(grep -E '^(DB_USERNAME|MYSQL_USER)=' "$env_file" | head -n 1 | cut -d'=' -f2- | tr -d '\r"' || echo "")
    db_pass=$(grep -E '^(DB_PASSWORD|MYSQL_PASSWORD)=' "$env_file" | head -n 1 | cut -d'=' -f2- | tr -d '\r"' || echo "")
    
    if [ -n "$db_name" ] && [ -n "$db_user" ] && [ -n "$db_pass" ] && [ "$db_user" != "root" ]; then
        APP_DBS["$db_name"]="${db_user}:${db_pass}"
    fi
done

log_info "Memeriksa koneksi database aplikasi menggunakan kredensial masing-masing..."

VERIFIED_DBS=()
for db in "${!APP_DBS[@]}"; do
    IFS=":" read -r user pass <<< "${APP_DBS[$db]}"
    if "${COMPOSE_CMD[@]}" mysql -u "$user" -p"$pass" -e "SELECT 1;" "$db" >/dev/null 2>&1; then
        log_success "Database ${BOLD}${db}${NC} terverifikasi (User: ${BOLD}${user}${NC})"
        VERIFIED_DBS+=("$db")
    fi
done

if [ ${#VERIFIED_DBS[@]} -eq 0 ]; then
    log_error "Tidak ada koneksi database aplikasi yang berhasil terverifikasi!"
    exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# TAHAP 2: Audit & Inventarisasi Database Aplikasi
# ─────────────────────────────────────────────────────────────────────────────
log_step "TAHAP 2: Audit & Inventarisasi Basis Data Aplikasi"

mkdir -p "${OUTPUT_DIR}/individual"
mkdir -p "${OUTPUT_DIR}/metadata"

echo "Daftar database aplikasi yang akan diekstrak:"
for db in "${VERIFIED_DBS[@]}"; do
    IFS=":" read -r user pass <<< "${APP_DBS[$db]}"
    echo -e "  • ${BOLD}${db}${NC} (User: ${user})"
done

printf "%s\n" "${VERIFIED_DBS[@]}" > "${OUTPUT_DIR}/metadata/databases_list.txt"

# Simpan metadata struktur tabel per aplikasi
log_info "Merekam baseline metadata tabel per aplikasi..."
SUMMARY_FILE="${OUTPUT_DIR}/metadata/baseline_table_summary.txt"
{
    echo "================================================================"
    echo "RSCH Platform — Baseline Metadata Tabel Aplikasi"
    echo "Timestamp: ${TIMESTAMP}"
    echo "================================================================"
    echo ""
    for db in "${VERIFIED_DBS[@]}"; do
        IFS=":" read -r user pass <<< "${APP_DBS[$db]}"
        echo "DATABASE: $db"
        echo "----------------------------------------------------------------"
        "${COMPOSE_CMD[@]}" mysql -u "$user" -p"$pass" -e "SHOW TABLES FROM \`$db\`;" "$db" 2>/dev/null || echo "Gagal mengambil daftar tabel."
        echo ""
    done
} > "$SUMMARY_FILE"
cat "$SUMMARY_FILE"

# ─────────────────────────────────────────────────────────────────────────────
# TAHAP 3: Ekstraksi Individual per Database Aplikasi
# ─────────────────────────────────────────────────────────────────────────────
log_step "TAHAP 3: Mengekstrak File SQL Terpisah per Aplikasi"

FULL_DUMP_FILE="${OUTPUT_DIR}/all_databases_${TIMESTAMP}.sql"
> "$FULL_DUMP_FILE"

for db in "${VERIFIED_DBS[@]}"; do
    IFS=":" read -r user pass <<< "${APP_DBS[$db]}"
    log_info "Mengekspor database: ${BOLD}${db}${NC} (User: ${user})..."
    DB_FILE="${OUTPUT_DIR}/individual/${db}.sql"
    
    "${COMPOSE_CMD[@]}" mysqldump -u "$user" -p"$pass" \
        --no-tablespaces \
        --single-transaction \
        --quick \
        --routines \
        --triggers \
        --events \
        --hex-blob \
        --max-allowed-packet=512M \
        --default-character-set=utf8mb4 "$db" > "$DB_FILE"
    
    # Checksum SHA256 untuk memvalidasi isi file nantinya
    sha256sum "$DB_FILE" > "${DB_FILE}.sha256"
    
    # Kompresi per DB
    gzip -c "$DB_FILE" > "${DB_FILE}.gz"
    
    FILE_SIZE=$(du -h "$DB_FILE" | cut -f1)
    log_success "Selesai: ${db}.sql (${FILE_SIZE})"
    
    # Gabungkan ke file monolithic dump
    cat "$DB_FILE" >> "$FULL_DUMP_FILE"
    echo -e "\n\n" >> "$FULL_DUMP_FILE"
done

# ─────────────────────────────────────────────────────────────────────────────
# TAHAP 4: Membuat Dump Gabungan (Combined Monolithic Dump)
# ─────────────────────────────────────────────────────────────────────────────
log_step "TAHAP 4: Membuat Dump Gabungan Seluruh Aplikasi"

FULL_SIZE=$(du -h "$FULL_DUMP_FILE" | cut -f1)
log_success "Full dump gabungan berhasil dibuat! Ukuran: ${BOLD}${FULL_SIZE}${NC}"

log_info "Mengompresi salinan full dump gabungan (gzip)..."
gzip -c "$FULL_DUMP_FILE" > "${FULL_DUMP_FILE}.gz"
GZ_SIZE=$(du -h "${FULL_DUMP_FILE}.gz" | cut -f1)
log_success "Arsip terkompresi selesai: ${FULL_DUMP_FILE}.gz (${GZ_SIZE})"

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
echo -e "${BOLD}${GREEN}   ✅ EKSTRAKSI DATABASE MYSQL APLIKASI SELESAI DENGAN SUKSES!${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "📁 Lokasi Penyimpanan : ${BOLD}${OUTPUT_DIR}${NC}"
echo -e "🔗 Symlink Shortcut   : ${BOLD}${LATEST_LINK}${NC}"
echo ""
echo -e "Struktur Hasil Ekstraksi:"
echo -e "  ├── ${BOLD}all_databases_${TIMESTAMP}.sql${NC}       (Dump gabungan seluruh aplikasi)"
echo -e "  ├── ${BOLD}all_databases_${TIMESTAMP}.sql.gz${NC}    (Arsip kompresi)"
echo -e "  ├── ${BOLD}individual/${NC}                       (Dump per aplikasi: siimut_db, ikp_db, iam_db)"
echo -e "  └── ${BOLD}metadata/${NC}                         (Daftar database & manifest tabel)"
echo ""
log_info "Tips restore database tertentu di lingkungan baru:"
echo -e "  ${YELLOW}mysql -u <app_user> -p < ${OUTPUT_DIR}/individual/<nama_db>.sql${NC}"
echo -e "${GREEN}================================================================${NC}\n"
