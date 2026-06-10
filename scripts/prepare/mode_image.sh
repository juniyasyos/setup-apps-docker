#!/usr/bin/env bash
# =============================================================================
# prepare/mode_image.sh — Mode 3: Gunakan Docker Image
# =============================================================================
# Meminta user input nama image:tag lalu mencatatnya ke .app-modes.
# Variabel yang diharapkan dari caller:
#   APP_NAME, PROJECT_DIR
# =============================================================================

# ──────────────────────────────────────────────
# File registry
# ──────────────────────────────────────────────
APP_MODES_FILE="${PROJECT_DIR}/.app-modes"

# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────

# Baca mode yang tersimpan untuk sebuah app
get_saved_image() {
    local target="$1"
    if [ ! -f "${APP_MODES_FILE}" ]; then
        echo ""
        return
    fi
    grep "^${target}=image:" "${APP_MODES_FILE}" 2>/dev/null \
        | head -1 \
        | sed "s|^${target}=image:||"
}

# Tulis / update entry di .app-modes
save_app_mode() {
    local target="$1"
    local value="$2"    # format: mode:detail

    # Buat file jika belum ada
    if [ ! -f "${APP_MODES_FILE}" ]; then
        cat > "${APP_MODES_FILE}" << 'HEADER'
# =============================================================================
# .app-modes — App Prepare Mode Registry
# =============================================================================
# Format: <app_name>=<mode>:<value>
#
# Mode:
#   image:<image:tag>   — menggunakan Docker image dari registry
#   clone:<repo_url>    — clone repo & build dari source
#   dockerfile:<stack>  — generate Dockerfile dari template
#
# File ini aman untuk di-commit (tidak mengandung secret).
# =============================================================================
HEADER
    fi

    # Hapus entry lama jika ada, lalu append baru
    local tmp_file
    tmp_file=$(mktemp)
    grep -v "^${target}=" "${APP_MODES_FILE}" > "${tmp_file}" 2>/dev/null || true
    echo "${target}=${value}" >> "${tmp_file}"
    mv "${tmp_file}" "${APP_MODES_FILE}"
}

# ──────────────────────────────────────────────
# Validasi format image:tag (basic)
# ──────────────────────────────────────────────
validate_image_ref() {
    local ref="$1"
    # Minimal harus ada karakter alphanumeric + optional registry/tag
    if [[ "$ref" =~ ^[a-zA-Z0-9_.-][a-zA-Z0-9_./:@-]*$ ]]; then
        return 0
    fi
    return 1
}

# ──────────────────────────────────────────────
# Main entry point untuk mode ini
# ──────────────────────────────────────────────
run_mode_image() {
    log_header "🚀 Docker Image: ${APP_NAME}"

    # Tampilkan nilai tersimpan jika ada
    local saved_image
    saved_image=$(get_saved_image "${APP_NAME}")

    if [ -n "${saved_image}" ]; then
        echo ""
        echo -e "  ${BLUE}ℹ️  Image tersimpan sebelumnya: ${CYAN}${saved_image}${NC}"
        echo ""
        echo "  K) Keep  — gunakan image yang tersimpan"
        echo "  U) Update — masukkan image baru"
        echo ""
        local action
        while true; do
            action=""
            read -rp "  Pilihan [K/u]: " action </dev/tty || action=""
            action="${action:-K}"
            case "${action^^}" in
                K)
                    echo ""
                    echo -e "  ${GREEN}✅ Menggunakan image: ${CYAN}${saved_image}${NC}"
                    _show_image_summary "${saved_image}"
                    return 0
                    ;;
                U) break ;;
                *) echo -e "  ${RED}❌ Pilihan tidak valid.${NC}" ;;
            esac
        done
    fi

    # ── Prompt input image ────────────────────────────────────────────────────
    echo ""
    echo "  Masukkan Docker image name:tag yang akan digunakan."
    echo ""
    echo -e "  ${BLUE}Contoh:${NC}"
    echo "    ghcr.io/juniyasyos/${APP_NAME}:latest"
    echo "    registry.hub.docker.com/myorg/${APP_NAME}:v1.0.0"
    echo "    ${APP_NAME}:latest"
    echo ""

    local image_ref
    image_ref=""
    while true; do
        read -rp "  Image [${APP_NAME}:latest]: " image_ref </dev/tty || image_ref=""
        image_ref="${image_ref:-${APP_NAME}:latest}"

        if validate_image_ref "${image_ref}"; then
            break
        else
            echo -e "  ${RED}❌ Format image tidak valid. Gunakan format: [registry/]name:tag${NC}"
        fi
    done

    # ── Simpan ke .app-modes ─────────────────────────────────────────────────
    save_app_mode "${APP_NAME}" "image:${image_ref}"
    log_success "Image dicatat di .app-modes: ${APP_NAME}=image:${image_ref}"

    _show_image_summary "${image_ref}"
}

# ── Summary box ──────────────────────────────────────────────────────────────
_show_image_summary() {
    local img="$1"
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────┐"
    echo "  │ ✅  Image berhasil dicatat!                             │"
    echo "  │                                                         │"
    printf "  │  🐳 %-54s │\n" "${img}"
    echo "  │                                                         │"
    echo "  │  Catatan tersimpan di: .app-modes                       │"
    echo "  │                                                         │"
    echo "  │  Untuk menarik image:                                   │"
    printf "  │    docker pull %-40s │\n" "${img}"
    echo "  └─────────────────────────────────────────────────────────┘"
    echo ""
}
