#!/bin/bash

# Warna
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}======================================================${NC}"
echo -e "${CYAN}    Pengecekan Jaringan Docker (Bentrok & Unused)    ${NC}"
echo -e "${CYAN}======================================================${NC}"
echo ""

TARGET_SUBNET="172.20.0.0/16"
TARGET_PREFIX="172.20"

echo -e "${YELLOW}🔍 1. Memeriksa network yang berbenturan dengan subnet target (${TARGET_SUBNET})...${NC}"

OVERLAPPING=()

# Mengambil semua network kustom
for net in $(docker network ls -q); do
    SUBNET=$(docker network inspect -f '{{range .IPAM.Config}}{{.Subnet}}{{end}}' $net 2>/dev/null)
    NAME=$(docker network inspect -f '{{.Name}}' $net 2>/dev/null)
    
    if [[ "$SUBNET" == *"$TARGET_PREFIX"* ]]; then
        # Abaikan network milik rsch-apps sendiri
        if [[ "$NAME" != "rsch-apps_default" && "$NAME" != "rsch-storage" ]]; then
            OVERLAPPING+=("$NAME|$SUBNET")
        fi
    fi
done

if [ ${#OVERLAPPING[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ Tidak ditemukan network lain yang menggunakan subnet ${TARGET_SUBNET}.${NC}"
else
    echo -e "${RED}⚠️  Ditemukan network yang berbenturan (Overlapping):${NC}"
    for item in "${OVERLAPPING[@]}"; do
        name="${item%%|*}"
        subnet="${item##*|}"
        echo -e "   - Network: ${YELLOW}$name${NC} (Subnet: $subnet)"
    done
    echo ""
    read -p "Apakah Anda ingin menghapus network yang berbenturan ini? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        for item in "${OVERLAPPING[@]}"; do
            name="${item%%|*}"
            echo "🗑️  Menghapus network $name..."
            docker network rm "$name" || echo -e "${RED}❌ Gagal menghapus $name (Mungkin sedang digunakan oleh container).${NC}"
        done
    else
        echo -e "⏭️  Penghapusan dibatalkan."
    fi
fi

echo ""
echo -e "${YELLOW}🔍 2. Memeriksa network kustom yang tidak digunakan (Unused / tidak ada container)...${NC}"
UNUSED_NETS=()
for net in $(docker network ls --filter type=custom -q); do
    NAME=$(docker network inspect -f '{{.Name}}' $net 2>/dev/null)
    CONTS=$(docker network inspect -f '{{len .Containers}}' $net 2>/dev/null)
    if [ "$CONTS" -eq 0 ]; then
        UNUSED_NETS+=("$NAME")
    fi
done

if [ ${#UNUSED_NETS[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ Tidak ada network kustom yang unused.${NC}"
else
    echo -e "${YELLOW}⚠️  Ditemukan network yang tidak memiliki container aktif:${NC}"
    for name in "${UNUSED_NETS[@]}"; do
        echo -e "   - $name"
    done
    echo ""
    read -p "Apakah Anda ingin menghapus network yang tidak digunakan ini? (y/N): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        for name in "${UNUSED_NETS[@]}"; do
            echo "🗑️  Menghapus $name..."
            docker network rm "$name"
        done
        echo -e "${GREEN}✅ Selesai menghapus network yang tidak digunakan.${NC}"
    else
        echo -e "⏭️  Penghapusan dibatalkan."
    fi
fi

echo ""
echo -e "${GREEN}✨ Pemeriksaan selesai!${NC}"
