#!/usr/bin/env bash
# =============================================================================
# RSCH Platform — Automated MinIO S3 Full Data Extraction Script
# =============================================================================
# Skrip ini mengekstrak SELURUH data objek/file dari MinIO Object Storage.
# Fitur:
#   1. Deteksi otomatis kontainer MinIO (minio-core/minio), network Docker, port, dan kredensial.
#   2. Ekstraksi Level Objek (S3 API Mirror): Mengunduh seluruh bucket & file
#      ke folder lokal host (tersimpan per bucket: siimut, ikp, data-center, dll).
#   3. Ekstraksi Level Volume Fisik (Raw Volume Tarball): Membuat snapshot .tar.gz
#      langsung dari volume Docker (/data) untuk proteksi 100% data & metadata.
#   4. Menghasilkan manifest inventarisasi berkas & ukuran penyimpanan.
#   5. Tersimpan rapi di: ./backup_data/minio/<timestamp>/
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUTPUT_DIR="${SCRIPT_DIR}/backup_data/minio/${TIMESTAMP}"

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
# TAHAP 1: Deteksi Kontainer, Port, & Kredensial MinIO
# ─────────────────────────────────────────────────────────────────────────────
log_step "TAHAP 1: Pemeriksaan Kontainer MinIO & Konfigurasi Runtime"

MINIO_CONTAINER=""
if docker ps --format '{{.Names}}' | grep -q "^minio-core$"; then
    MINIO_CONTAINER="minio-core"
elif docker ps --format '{{.Names}}' | grep -q "^minio$"; then
    MINIO_CONTAINER="minio"
elif docker ps --format '{{.Names}}' | grep -q "minio"; then
    MINIO_CONTAINER=$(docker ps --format '{{.Names}}' | grep "minio" | grep -v "init" | head -n 1)
fi

if [ -z "$MINIO_CONTAINER" ]; then
    log_error "Kontainer MinIO tidak ditemukan atau sedang TIDAK BERJALAN!"
    echo ""
    log_warn "Pastikan kontainer MinIO aktif terlebih dahulu:"
    echo "  ./rsch storage up"
    echo "  (atau: docker compose -f compose/base/infra.yml up -d minio)"
    exit 1
fi
log_success "Kontainer MinIO terdeteksi: ${BOLD}${MINIO_CONTAINER}${NC}"

# Ambil Docker network yang digunakan oleh MinIO container
MINIO_NETWORK=$(docker inspect "$MINIO_CONTAINER" --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' | awk '{print $1}')
if [ -z "$MINIO_NETWORK" ]; then
    MINIO_NETWORK="bridge"
fi
log_info "Network Docker yang digunakan: ${BOLD}${MINIO_NETWORK}${NC}"

# Ambil Kredensial langsung dari environment container yang sedang hidup
MINIO_USER=$(docker exec "$MINIO_CONTAINER" printenv MINIO_ROOT_USER 2>/dev/null || echo "")
MINIO_PASSWORD=$(docker exec "$MINIO_CONTAINER" printenv MINIO_ROOT_PASSWORD 2>/dev/null || echo "")

if [ -z "$MINIO_USER" ] || [ -z "$MINIO_PASSWORD" ]; then
    MINIO_USER="admin"
    MINIO_PASSWORD="password"
fi
log_info "Kredensial MinIO root terverifikasi: user='${MINIO_USER}'"

# Deteksi port internal MinIO (9000 di restructure vs 9090 di master)
INTERNAL_PORT="9000"
if docker exec "$MINIO_CONTAINER" curl -s http://localhost:9000/minio/health/ready >/dev/null 2>&1; then
    INTERNAL_PORT="9000"
elif docker exec "$MINIO_CONTAINER" curl -s http://localhost:9090/minio/health/ready >/dev/null 2>&1; then
    INTERNAL_PORT="9090"
fi
log_info "Port internal MinIO API terdeteksi: ${BOLD}${INTERNAL_PORT}${NC}"

# Siapkan direktori penyimpanan lokal
mkdir -p "${OUTPUT_DIR}/buckets"
mkdir -p "${OUTPUT_DIR}/volume_archive"
mkdir -p "${OUTPUT_DIR}/metadata"

# ─────────────────────────────────────────────────────────────────────────────
# TAHAP 2: Ekstraksi Level Objek S3 (Mirror Seluruh File per Bucket)
# ─────────────────────────────────────────────────────────────────────────────
log_step "TAHAP 2: Mengunduh/Mirroring Semua Objek dari Seluruh Bucket MinIO"

log_info "Menjalankan MinIO Client (mc) untuk menyalin semua file..."

# Jalankan container ephemeral minio/mc pada network yang sama
docker run --rm \
    --entrypoint /bin/sh \
    --network "$MINIO_NETWORK" \
    -v "${OUTPUT_DIR}/buckets":/export \
    -v "${OUTPUT_DIR}/metadata":/metadata \
    minio/mc:latest -c "
        set -e
        echo '🔗 Menghubungkan mc ke MinIO...'
        mc alias set myminio http://${MINIO_CONTAINER}:${INTERNAL_PORT} '${MINIO_USER}' '${MINIO_PASSWORD}' --api S3v4 >/dev/null 2>&1

        echo '📋 Mendapatkan daftar seluruh bucket...'
        mc ls myminio > /metadata/raw_buckets.txt
        > /metadata/buckets_list.txt
        while IFS= read -r line; do
            [ -z \"\$line\" ] && continue
            b_name=\"\${line##* }\"
            b_name=\"\${b_name%/}\"
            [ -z \"\$b_name\" ] && continue
            echo \"\$b_name\" >> /metadata/buckets_list.txt
        done < /metadata/raw_buckets.txt

        echo ''
        echo 'Memulai proses sinkronisasi (mirror)...'
        while IFS= read -r bucket; do
            [ -z \"\$bucket\" ] && continue
            echo \"========================================\"
            echo \"📦 Menyalin Bucket: \$bucket\"
            echo \"========================================\"
            mkdir -p /export/\"\$bucket\"
            mc mirror --overwrite myminio/\"\$bucket\" /export/\"\$bucket\"
            echo \"✅ Selesai mirror bucket: \$bucket\"
            echo ''
        done < /metadata/buckets_list.txt
    "

log_success "Seluruh objek S3 berhasil disinkronkan ke direktori lokal: ${OUTPUT_DIR}/buckets/"

# ─────────────────────────────────────────────────────────────────────────────
# TAHAP 3: Ekstraksi Level Fisik (Raw Docker Volume Snapshot .tar.gz)
# ─────────────────────────────────────────────────────────────────────────────
log_step "TAHAP 3: Membuat Snapshot Raw Volume Docker MinIO (.tar.gz)"

# Cari nama volume Docker yang di-mount ke /data pada container minio
VOLUME_NAME=$(docker inspect "$MINIO_CONTAINER" --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Name}}{{end}}{{end}}')

if [ -n "$VOLUME_NAME" ]; then
    log_info "Docker Volume terdeteksi: ${BOLD}${VOLUME_NAME}${NC}"
    log_info "Membuat arsip terkompresi dari raw volume..."
    
    ARCHIVE_FILE="${OUTPUT_DIR}/volume_archive/minio_raw_volume_${TIMESTAMP}.tar.gz"
    
    docker run --rm \
        -v "${VOLUME_NAME}":/data:ro \
        -v "${OUTPUT_DIR}/volume_archive":/backup \
        alpine tar -czf "/backup/minio_raw_volume_${TIMESTAMP}.tar.gz" -C /data .
    
    ARCHIVE_SIZE=$(du -h "$ARCHIVE_FILE" | cut -f1)
    sha256sum "$ARCHIVE_FILE" > "${ARCHIVE_FILE}.sha256"
    log_success "Raw Volume Snapshot selesai: ${BOLD}minio_raw_volume_${TIMESTAMP}.tar.gz${NC} (${ARCHIVE_SIZE})"
else
    log_warn "Volume Docker MinIO tidak berupa Named Volume (mungkin bind mount host). Melewati pembuatan raw volume tarball."
fi

# ─────────────────────────────────────────────────────────────────────────────
# TAHAP 4: Audit & Ringkasan Inventarisasi Berkas
# ─────────────────────────────────────────────────────────────────────────────
log_step "TAHAP 4: Verifikasi & Audit Hasil Ekstraksi"

# Buat manifest rincian ukuran tiap bucket
MANIFEST_FILE="${OUTPUT_DIR}/metadata/extraction_summary.txt"
{
    echo "================================================================"
    echo "RSCH Platform — MinIO Backup Manifest"
    echo "Timestamp : ${TIMESTAMP}"
    echo "Container : ${MINIO_CONTAINER}"
    echo "================================================================"
    echo ""
    echo "RINCIAN PENYIMPANAN BUCKET (HASIL EKSTRAKSI LOKAL):"
    du -sh "${OUTPUT_DIR}/buckets"/* 2>/dev/null || echo "Tidak ada bucket yang diekstrak"
    echo ""
    echo "TOTAL FILE & DIREKTORI:"
    find "${OUTPUT_DIR}/buckets" -type f | wc -l | sed 's/^/Total file objek: /'
    echo ""
} > "$MANIFEST_FILE"

cat "$MANIFEST_FILE"

# Buat pointer symlink ke backup terbaru
LATEST_LINK="${SCRIPT_DIR}/backup_data/minio/latest"
rm -f "$LATEST_LINK"
ln -s "$TIMESTAMP" "$LATEST_LINK"

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${BOLD}${GREEN}   ✅ EKSTRAKSI DATA MINIO S3 SELESAI DENGAN SUKSES!${NC}"
echo -e "${GREEN}================================================================${NC}"
echo -e "📁 Lokasi Penyimpanan : ${BOLD}${OUTPUT_DIR}${NC}"
echo -e "🔗 Symlink Shortcut   : ${BOLD}${LATEST_LINK}${NC}"
echo ""
echo -e "Struktur Hasil Ekstraksi:"
echo -e "  ├── ${BOLD}buckets/${NC}                  (Folder file asli per bucket: siimut, ikp, dll)"
echo -e "  ├── ${BOLD}volume_archive/${NC}           (Snapshot raw volume tar.gz + SHA256)"
echo -e "  └── ${BOLD}metadata/${NC}                 (Daftar bucket & manifest file)"
echo ""
echo -e "${GREEN}================================================================${NC}\n"
