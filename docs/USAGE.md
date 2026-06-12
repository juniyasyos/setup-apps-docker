# Panduan Penggunaan Lengkap — RSCH Application Platform Orchestrator

Dokumen ini menjelaskan alur kerja operasional, konfigurasi sistem, dan proses pemeliharaan harian pada platform deployment multi-aplikasi **Rumah Sakit Citra Husada (RSCH)**.

---

## 📋 Daftar Isi

1. [Arsitektur & Topologi Layanan](#1-arsitektur--topologi-layanan)
2. [Prasyarat & Persiapan Sistem](#2-prasyarat--persiapan-sistem)
3. [Panduan Memulai Cepat (Quick Start)](#3-panduan-memulai-cepat-quick-start)
4. [Referensi Perintah CLI (`./rsch`)](#4-referensi-perintah-cli-rsch)
5. [Alur Kerja Mode Persiapan Aplikasi (Prepare Modes)](#5-alur-kerja-mode-persiapan-aplikasi-prepare-modes)
6. [Manajemen Environment & Secrets](#6-manajemen-environment--secrets)
7. [Prosedur Build & Registrasi Image](#7-prosedur-build--registrasi-image)
8. [Panduan Diagnostik & Troubleshooting](#8-panduan-diagnostik--troubleshooting)
9. [Panduan Menambahkan Aplikasi Baru](#9-panduan-menambahkan-aplikasi-baru)
10. [Daftar Referensi File Konfigurasi](#10-daftar-referensi-file-konfigurasi)

---

## 1. Arsitektur & Topologi Layanan

Platform ini mengintegrasikan seluruh aplikasi ke dalam satu orkestrator kontainer menggunakan Docker Compose. Jaringan diisolasi menggunakan subnet khusus agar lalu lintas internal tidak dapat diakses secara langsung dari luar host tanpa melalui Nginx reverse proxy.

```
                            🌐 Internet / LAN
                                    │
                            ┌───────▼───────┐
                            │  Port 80/443  │
                            └───────┬───────┘
                                    │
                        ┌───────────▼───────────┐
                        │   Nginx Reverse Proxy │ (container: multi-web)
                        └───────────┬───────────┘
                                    │ (Rute internal via Virtual Host)
           ┌────────────────────────┼────────────────────────┬────────────────────────┐
           │                        │                        │                        │
  ┌────────▼────────┐      ┌────────▼────────┐      ┌────────▼────────┐      ┌────────▼────────┐
  │  SIIMUT App     │      │  IAM Server     │      │  IKP App        │      │  LMS App        │
  │  (Port: 8000)   │      │  (Port: 8100)   │      │  (Port: 8200)   │      │  (Port: 7000)   │
  └────────┬────────┘      └────────┬────────┘      └────────┬────────┘      └─────────────────┘
           │                        │                        │
  ┌────────▼────────┐      ┌────────▼────────┐      ┌────────▼────────┐
  │  Queue Worker   │      │  Queue Worker   │      │  Queue Worker   │
  │  Scheduler      │      │  Scheduler      │      │  Scheduler      │
  └─────────────────┘      └─────────────────┘      └─────────────────┘
           │                        │                        │
           └────────────────────────┼────────────────────────┘
                                    │ (Koneksi Jaringan Internal)
                        ┌───────────▼───────────┐
                        │   Layanan Bersama     │
                        ├───────────────────────┤
                        │ • MySQL Database      │ (container: database-service)
                        │ • MinIO S3 Storage    │ (container: minio)
                        │ • phpMyAdmin          │ (container: phpmyadmin - dev only)
                        └───────────────────────┘
```

---

## 2. Prasyarat & Persiapan Sistem

Sebelum menjalankan platform, pastikan host Anda memenuhi spesifikasi berikut:

| Kebutuhan | Minimal | Catatan |
| :--- | :--- | :--- |
| **Sistem Operasi** | Linux (Ubuntu Server 20.04/22.04 LTS direkomendasikan) | Mendukung kernel modern untuk filesystem overlay2 |
| **Docker Engine** | Version 24.x atau lebih tinggi | Memerlukan Docker Compose v2 (fitur `include` & `extends`) |
| **Spesifikasi Hardware**| 4 Cores CPU, 8 GB RAM (Development) / 16 GB RAM (Production) | Dibutuhkan untuk menjalankan database, S3, proxy, dan seluruh (7) aplikasi bersamaan |
| **Utilitas Host** | Git, OpenSSL, bash v4+ | Diperlukan oleh skrip automasi pengelola platform |

### Instalasi Docker Otomatis
Jika host belum terpasang Docker, Anda dapat memasangnya menggunakan skrip installer bawaan:
```bash
chmod +x rsch
./rsch scripts/prepare/install-docker.sh
```

---

## 3. Panduan Memulai Cepat (Quick Start)

Langkah berurutan untuk menyalakan seluruh platform dari keadaan bersih:

### Langkah 1: Kloning Repositori Platform
```bash
git clone <repository-url-platform> rsch-apps
cd rsch-apps
```

### Langkah 2: Buat Environment Konfigurasi Awal
```bash
# Salin konfigurasi utama platform
cp .env.example .env

# Salin konfigurasi port dan IP Host untuk dev dan prod
cp env/dev.env.example env/dev.env
cp env/prod.env.example env/prod.env
```
> [!IMPORTANT]
> Sesuaikan nilai `HOST_IP` di dalam file `env/dev.env` dan `env/prod.env` dengan alamat IP server lokal/produksi Anda agar redirection SSO dan reverse proxy Nginx berjalan dengan benar.

### Langkah 3: Nyalakan Base Infrastructure
```bash
./rsch infra up
```
*Skrip ini akan memicu pembuatan volume penyimpanan, jaringan lokal, menyalakan MySQL, MinIO S3, dan Nginx.*

### Langkah 4: Jalankan Persiapan Aplikasi (Prepare)
```bash
# Jalankan prepare interaktif untuk tiap aplikasi
./rsch prepare siimut
./rsch prepare iam
./rsch prepare ikp
./rsch prepare lms
./rsch prepare smsp
./rsch prepare fe-smsp
./rsch prepare rbv

# Atau siapkan semuanya sekaligus (interaktif berurutan)
./rsch prepare all
```

### Langkah 5: Start Service Aplikasi secara Penuh
```bash
# Untuk mode Development (Default)
./rsch up

# Untuk mode Production (Port standar, APP_DEBUG dinonaktifkan)
./rsch up --prod
```

---

## 4. Referensi Perintah CLI (`./rsch`)

CLI `./rsch` adalah pembungkus perintah Docker Compose. Semua konfigurasi dimuat secara otomatis di belakang layar.

### Sintaks Umum
```bash
./rsch <command> [argument/options]
```

### Daftar Perintah Terintegrasi

| Perintah | Deskripsi | Argumen Tambahan |
| :--- | :--- | :--- |
| `list` | Menampilkan semua aplikasi terdaftar di `repos.csv` | - |
| `prepare` | Memulai inisialisasi aplikasi baru/lama | `<app>` / `all` / `--no-deps` |
| `scaffold` | Membuat file boilerplate untuk aplikasi baru | `<new_app>` |
| `build` | Mengompilasi image Docker lokal untuk aplikasi | `<app>` / `all` [opsional: `push`] |
| `up` | Menyalakan service aplikasi dan proxy | `--dev` (default) atau `--prod` |
| `down` | Mematikan service aplikasi dan proxy | -- |
| `restart` | Me-restart kontainer app, worker, dan scheduler | `<app>` |
| `logs` | Menampilkan logs runtime secara realtime (tail 100) | `<app>` |
| `health` | Menjalankan skrip validasi status dan konektivitas | `<app>` |
| `infra` | Mengontrol siklus hidup database, S3, dan proxy saja | `up` / `down` / `restart` |

---

## 5. Alur Kerja Mode Persiapan Aplikasi (Prepare Modes)

Skrip `./rsch prepare` memiliki **tiga mode persiapan** interaktif yang dirancang untuk skenario deployment yang berbeda.

```
                          [ ./rsch prepare <app> ]
                                      │
                         Pilih Mode Setup Terminal
                                      │
         ┌────────────────────────────┼────────────────────────────┐
         ▼                            ▼                            ▼
[ 1: Generate Dockerfile ]     [ 2: Clone & Build ]       [ 3: Use Docker Image ]
  • Laravel template             • Ambil kode Git           • Tanpa compile lokal
  • Buat entrypoint.sh           • Compile assets           • Input Image:Tag
  • Skip/Replace jika ada        • Generate secrets         • Simpan ke .app-modes
```

---

### 1️⃣ Mode 1: Generate Dockerfile
*   **Tujuan**: Membuat konfigurasi penulisan kontainer Docker kustom di folder host untuk kemudian dikompilasi sendiri.
*   **Prosedur**:
    1.  Menanyakan framework target (saat ini default ke **Laravel**).
    2.  Mengecek keberadaan `docker/<app>/Dockerfile`. Jika sudah ada, sistem memunculkan prompt:
        *   `S` (Skip): Mempertahankan file yang sudah ada.
        *   `R` (Replace): Menimpa file lama dengan template PHP-Alpine JIT bawaan.
    3.  Membuat berkas `docker/<app>/entrypoint.sh` untuk otomasi cache clearing dan checking koneksi database saat kontainer berjalan.

### 2️⃣ Mode 2: Clone Repo & Build (Kompilasi dari Source Code)
*   **Tujuan**: Men-deploy aplikasi secara langsung dari kode sumber Git terbaru.
*   **Prosedur**:
    1.  **Git Phase**: Mengecek `sources/<app>`. Jika sudah ada repositori Git, user diberikan prompt:
        *   `S` (Skip): Abaikan git pull, gunakan source code lokal yang ada.
        *   `P` (Pull): Lakukan `git pull origin <branch>` untuk memperbarui kode.
        *   `R` (Reset): Jalankan `git reset --hard origin/<branch>` untuk membuang perubahan lokal dan menarik versi terbaru dari server.
    2.  **Environment Phase**: Menyalin `.env.example` ke `.env` lokal pada folder source code. User dapat memilih opsi skip atau overwrite file `.env`.
    3.  **Dependencies Phase**: Menjalankan `composer install` dan `npm install && npm run build` untuk mengompilasi aset front-end (kecuali jika flag `--no-deps` digunakan).
    4.  **Production Secrets Generation**: Membuat file `.env.prod.<app>` di folder `env/` yang berisi sandi acak dan kunci kriptografi yang aman.

### 3️⃣ Mode 3: Gunakan Docker Image (Deployment Cepat Tanpa Kode Sumber)
*   **Tujuan**: Menjalankan aplikasi langsung dari image yang sudah di-compile di repositori cloud (misal Docker Hub / GHCR). Skenario ini sangat ideal untuk server production guna menghindari proses compile aset yang memakan memori CPU server.
*   **Prosedur**:
    1.  Mengecek apakah sudah ada catatan image tersimpan di `.app-modes`. Jika ada, user ditanya apakah ingin mempertahankan (`Keep`) atau memperbarui (`Update`).
    2.  Meminta input teks alamat image lengkap beserta tag-nya (contoh: `ghcr.io/juniyasyos/siimut:v2.0.0`).
    3.  Menyimpan pasangan konfigurasi tersebut ke berkas `.app-modes` agar docker-compose merujuk ke image eksternal ini saat proses startup dijalankan.

---

## 6. Manajemen Environment & Secrets

Konfigurasi keamanan dirancang berlapis menggunakan pemisahan file environment di direktori `env/`:

```
env/
├── common.env               # Global: Kredensial root database MySQL
├── dev.env                  # Dev: Port map (kepala 8xx10) & IP Host lokal
├── prod.env                 # Prod: Port map (kepala 8xx00) & IP Host production
└── .env.prod.<app>          # Dinamis: Secrets unik hasil generate (Gitignored)
```

> [!CAUTION]
> File `.env.prod.*` berisi data kredensial rahasia (seperti kunci enkripsi aplikasi, sandi database unik, dan private key). File ini secara otomatis didaftarkan ke `.gitignore`. **JANGAN PERNAH** menghapus baris tersebut atau memasukkan berkas-berkas ini ke dalam repositori Git!

### Kunci Enkripsi Khusus (Otomatisasi Prepare)

Saat persiapan aplikasi di Mode 2 dijalankan, beberapa rahasia berikut akan di-generate secara otomatis:
1.  **`APP_KEY`**: Enkripsi bawaan Laravel (menggunakan `openssl` secure byte generator).
2.  **`DB_PASSWORD` & `MYSQL_ROOT_PASSWORD`**: Sandi acak base64 sepanjang 16 karakter.
3.  **`IAM_JWT_SECRET`**: Digunakan untuk validasi token OAuth2 JWT. Khusus untuk aplikasi **SIIMUT**, skrip prepare akan secara otomatis membaca dan menyinkronkan nilai JWT secret yang ada dari berkas `env/.env.prod.iam` agar integrasi SSO langsung terjalin tanpa konfigurasi manual.
4.  **Passport RSA Keys (Khusus IAM Server)**: Laravel Passport memerlukan berkas kunci privat dan publik RSA. Skrip akan membuat sepasang kunci enkripsi 2048-bit dan menulisnya ke dalam berkas `env/.env.prod.iam` dengan format multi-line yang aman.

---

## 7. Prosedur Build & Registrasi Image

Proses kompilasi image Docker diatur secara sentral di file `compose/build.yml`. Anda dapat memicu build dengan perintah rsch CLI:

```bash
# Build image SIIMUT secara lokal
./rsch build siimut

# Build dan berikan tag terbaru kemudian push ke Docker Hub
# (Pastikan Anda sudah login ke Docker menggunakan perintah 'docker login')
DOCKER_HUB_USER=namauser ./rsch build siimut push

# Build seluruh aplikasi dan push sekaligus
DOCKER_HUB_USER=namauser ./rsch build all push
```

### Override Versi Image
Secara default, skrip build akan membaca nomor versi yang tertulis di file metadata `apps/<app>/app.yml`. Anda bisa menimpanya dengan mendefinisikan environment variable saat kompilasi:
```bash
SIIMUT_VERSION=v2.5.0 ./rsch build siimut
```

---

## 8. Panduan Diagnostik & Troubleshooting

Jika terjadi gangguan operasional atau kegagalan konektivitas, gunakan langkah diagnostik berikut secara berurutan:

### Kontainer Mengalami Restart Loop
Gunakan perintah CLI logs untuk menganalisis error PHP runtime di awal boot:
```bash
./rsch logs siimut
```
Jika kontainer mati sebelum sempat menulis log, periksa menggunakan status docker engine:
```bash
docker compose ps app-siimut
```

### Masalah Koneksi Database (Connection Refused)
1.  Pastikan kontainer basis data terpusat menyala:
    ```bash
    ./rsch infra up
    ```
2.  Lakukan ping internal ke database menggunakan mysqladmin bawaan kontainer:
    ```bash
    docker compose -f compose/base/infra.yml exec db mysqladmin ping -uroot -prootpass123
    ```

### Masalah DNS / Rute Jaringan Docker
Jika aplikasi tidak dapat saling berkomunikasi (misal SIIMUT tidak bisa menghubungi IAM Server SSO), kemungkinan terjadi konflik alokasi IP di sistem Docker host Anda. Jalankan alat perbaikan jaringan:
```bash
./scripts/maintenance/fix-network.sh
```
*Skrip ini akan menghentikan seluruh kontainer, menghapus network virtual yang rusak, me-reset DNS lokal Docker daemon, dan menyalakan kembali interface network secara bersih.*

### Skrip Pemeriksaan Mandiri (Health Checks)
Jalankan modul penguji bawaan platform:
```bash
# Uji kesehatan otentikasi SSO IAM Server
./rsch health iam

# Uji integrasi file storage dengan MinIO S3
./scripts/health/check-minio.sh

# Diagnostik mandiri umum (Composer, Signatory, Livewire)
./scripts/maintenance/diagnose.sh
```

---

## 9. Panduan Menambahkan Aplikasi Baru

Untuk mendaftarkan aplikasi baru ke dalam platform manager, ikuti langkah-langkah di bawah ini:

### Langkah 1: Jalankan Perintah Scaffold
Jalankan CLI scaffold untuk membuat seluruh file boilerplate secara otomatis:
```bash
./rsch scaffold nama-app-baru
```
Terminal akan meminta input data secara interaktif:
*   **Nama Aplikasi & Deskripsi**
*   **URL Repositori Git & Target Branch**
*   **Port Forwarding** (Skrip secara otomatis mendeteksi port tertinggi yang terpakai dan menyarankan port kosong berikutnya).
*   **Spesifikasi Database** (Nama database, user, dan sandi).
*   **Opsi Driver**: Status penggunaan Queue Worker dan Scheduler Task.

Selesai mengisi, skrip scaffolding akan otomatis mengeksekusi Python parser di balik layar untuk melakukan injeksi blok konfigurasi secara dinamis ke berkas:
1.  `compose.yml` (Pendaftaran service dan volume persistent baru).
2.  `compose/base/web.yml` (Pendaftaran port binding dan permission folder public).
3.  `compose/build.yml` (Pendaftaran instruksi kompilasi image otomatis).

### Langkah 2: Daftarkan ke Konfigurasi Nginx Web
Edit berkas `docker/nginx/nginx-multi-apps.conf` untuk menambahkan routing subdomain/domain baru:
```nginx
server {
    listen 80;
    server_name nama-app-baru.local;

    location / {
        proxy_pass http://app-nama-app-baru:9000;
        include php_fastcgi_params; # Sesuaikan dengan format template
    }
}
```

### Langkah 3: Eksekusi Prepare dan Jalankan
```bash
# Siapkan aplikasi baru (Clone repo & build)
./rsch prepare nama-app-baru

# Khusus aplikasi frontend (seperti React/Vite) tanpa backend PHP:
# Sesuaikan 'framework' di apps/<nama>/app.yml menjadi react-vite

# Jalankan service kontainer baru
./rsch up
```

---

## 10. Daftar Referensi File Konfigurasi

| Lokasi File | Peran Utama | Kapan Harus Diedit |
| :--- | :--- | :--- |
| `compose.yml` | Konfigurasi utama aggregator kontainer aplikasi | Saat mendaftarkan service penunjang baru secara global |
| `compose/base/network.yml` | Konfigurasi subnet IP, driver volume, dan network | Saat ingin mengubah rentang IP subnet jaringan internal |
| `compose/base/web.yml` | Binds Nginx ports & volume caching bootstrap | Saat mengubah port utama web atau permission directory |
| `compose/base/database.yml` | Konfigurasi MySQL Server dan setup database | Saat melakukan upgrade versi image database engine |
| `compose/base/php-base.yml` | Template setingan dasar PHP PHP-FPM / Worker | Saat ingin mengubah batas memory limit dasar PHP kontainer |
| `docker/nginx/nginx.conf` | Konfigurasi dasar web server Nginx proxy | Saat ingin mengaktifkan gzip compression atau setting SSL |
| `docker/db/my.cnf` | Konfigurasi performa database MySQL | Saat tuning query cache database produksi |
| `repos.csv` | Daftar flat-file registry repositori Git tepercaya | Saat merubah alamat repositori URL Git aplikasi |
