# RSCH Application Platform & Deployment Orchestrator

[![Orchestration System](https://img.shields.io/badge/Orchestrator-v2.1.0--modular-blueviolet?style=for-the-badge)](https://github.com/juniyasyos/setup-apps-docker)
[![Docker Support](https://img.shields.io/badge/Docker-Engine%2024.x%2B%20%7C%20Compose%20v2-blue?style=for-the-badge&logo=docker)](https://docs.docker.com/engine/)
[![Laravel Stack](https://img.shields.io/badge/Laravel-PHP%208.4%20%7C%20Alpine-red?style=for-the-badge&logo=laravel)](https://laravel.com/)

Platform Docker multi-aplikasi modular yang dirancang untuk mengotomatisasi siklus hidup (lifecycle) deployment, monitoring, dan manajemen aplikasi internal di lingkungan **Rumah Sakit Citra Husada (RSCH)**. Platform ini mengintegrasikan Nginx reverse proxy, basis data terpusat, object storage S3-compatible, SSO server, dan runner antrean (queues/schedulers).

---

## 🏛️ Arsitektur Sistem & Topologi Network

Platform ini menggunakan topologi jaringan tersegregasi di mana seluruh kontainer aplikasi dan infrastruktur terhubung melalui satu *overlay-ready network* (`rsch-apps_default`). Nginx bertindak sebagai gerbang utama (Reverse Proxy) untuk merutekan lalu lintas eksternal ke masing-masing kontainer aplikasi berdasarkan pencocokan domain virtual host.

```mermaid
graph TD
    Client[Klien / Browser] -->|Port 80/443| Nginx[Nginx Reverse Proxy <br> container: multi-web]
    
    subgraph Jaringan Aplikasi (172.20.0.0/16)
        Nginx -->|siimut.local:8000| SIIMUT[SIIMUT App <br> container: siimut-app]
        Nginx -->|ikp.local:8200| IKP[IKP App <br> container: ikp-app]
        Nginx -->|iam.local:8100| IAM[IAM Server SSO <br> container: iam-app]
        Nginx -->|lms.local:7000| LMS[LMS CitraHusada <br> container: lms-app]
        
        SIIMUT -->|Queue / Schedule| SIIMUT_W[SIIMUT Worker/Scheduler]
        IKP -->|Queue / Schedule| IKP_W[IKP Worker/Scheduler]
        IAM -->|Queue / Schedule| IAM_W[IAM Worker/Scheduler]
        
        SIIMUT & IKP & IAM & LMS -->|Koneksi DB| MySQL[(MySQL 8.0 <br> database-service)]
        SIIMUT & IKP & IAM -->|Object Storage S3| MinIO[(MinIO S3 Engine)]
    end
    
    subgraph Layanan Administrator
        MySQL --- phpMyAdmin[phpMyAdmin <br> port: 8888]
    end

    classDef appNode fill:#f9f,stroke:#333,stroke-width:2px;
    classDef dbNode fill:#9f9,stroke:#333,stroke-width:2px;
    classDef proxyNode fill:#bbf,stroke:#333,stroke-width:2px;
    
    class SIIMUT,IKP,IAM,LMS appNode;
    class MySQL,MinIO dbNode;
    class Nginx proxyNode;
```

---

## 📦 Aplikasi Terkelola (Application Matrix)

Platform ini mengelola empat aplikasi inti dengan konfigurasi port dan domain sebagai berikut:

| Nama Aplikasi | Port Dev | Port Prod | Domain | Deskripsi Layanan | Prepare Modes |
| :--- | :---: | :---: | :--- | :--- | :--- |
| **[SIIMUT](apps/siimut/)** | `8010` | `8000` | `siimut.local` | Sistem Informasi Imunisasi Terpadu | Dockerfile / Clone / Registry Image |
| **[IAM Server](apps/iam/)** | `8110` | `8100` | `iam.local` | Authentication & SSO Server (OAuth2/Passport) | Dockerfile / Clone / Registry Image |
| **[IKP](apps/ikp/)** | `8210` | `8200` | `ikp.local` | Incident Reporting & Pelaporan Insiden RS | Dockerfile / Clone / Registry Image |
| **[LMS](apps/lms/)** | `7000` | `7000` | `lms.local` | Learning Management System Citra Husada | Dockerfile / Clone / Registry Image |

---

## 🛠️ CLI Orchestration Engine (`./rsch`)

Platform ini dilengkapi dengan CLI wrapper khusus bernama `rsch` di root direktori untuk mempermudah eksekusi instruksi. Anda tidak perlu mengetik sintaks `docker compose` yang panjang.

### Panduan Perintah CLI

```bash
# =========================================================================
# 1. PENGELOLAAN SIKLUS HIDUP APLIKASI
# =========================================================================
./rsch list                 # Menampilkan daftar aplikasi yang terdaftar di repos.csv
./rsch prepare <app>        # Siapkan aplikasi dengan 3 opsi mode interaktif (lihat detail di bawah)
./rsch prepare all          # Menyiapkan seluruh aplikasi secara berurutan
./rsch scaffold <app>       # Membuat struktur direktori dan file konfigurasi baru untuk aplikasi baru

# =========================================================================
# 2. BUILD & COMPILE IMAGE
# =========================================================================
./rsch build <app>          # Build Docker image lokal menggunakan apps/<app>/Dockerfile
./rsch build <app> push     # Build lokal kemudian langsung unggah (push) ke Docker Hub registry
./rsch build all push       # Build dan push semua image aplikasi sekaligus

# =========================================================================
# 3. MANAJEMEN RUNTIME (DOCKER COMPOSE RUNNER)
# =========================================================================
./rsch up                   # Jalankan semua service di latar belakang dalam mode Development (--dev)
./rsch up --prod            # Jalankan semua service dalam mode Production (menggunakan port utama & env produksi)
./rsch down                 # Matikan seluruh kontainer (volume data tetap aman dan presisten)
./rsch restart <app>        # Restart service spesifik aplikasi (app, worker, dan scheduler-nya)

# =========================================================================
# 4. INFRASTRUKTUR SAJA (DATABASE, STORAGE, PROXY)
# =========================================================================
./rsch infra up             # Nyalakan base infrastructure saja (MySQL, MinIO, Nginx Proxy, phpMyAdmin)
./rsch infra down           # Matikan seluruh service base infrastructure
./rsch infra restart        # Restart seluruh service base infrastructure

# =========================================================================
# 5. DIAGNOSTIK & MONITORING
# =========================================================================
./rsch logs <app>           # Stream output logs untuk aplikasi dan queue worker-nya (--tail=100)
./rsch health <app>         # Jalankan skrip verifikasi konektivitas dan kesehatan aplikasi
```

---

## ⚡ Alur Kerja Persiapan Aplikasi (Interactive Prepare Modes)

Saat Anda menjalankan perintah `./rsch prepare <app>`, sistem akan memandu Anda secara interaktif melalui terminal menu untuk memilih salah satu dari **tiga mode persiapan**:

### 1️⃣ Mode 1: Generate Dockerfile
*   **Kapan digunakan**: Ketika Anda ingin membuat instruksi Dockerfile kustom untuk aplikasi Anda agar bisa di-build sendiri di server target.
*   **Proses**: Menyalin konfigurasi template Dockerfile berbasis PHP 8.4 Alpine + Nginx-ready extension ke `docker/<app>/Dockerfile` dan membuat `entrypoint.sh` kustom. Jika file sudah ada, sistem akan menanyakan konfirmasi `Skip` atau `Replace` (timpa).

### 2️⃣ Mode 2: Clone Repo & Build (Source Code Mode)
*   **Kapan digunakan**: Ketika Anda ingin men-deploy dari kode sumber Git terbaru secara langsung.
*   **Proses**: 
    1.  Mengecek folder `sources/<app>`. Jika sudah ada, sistem memberikan opsi: `Skip` (lewati), `Pull` (update kode), atau `Reset` (buang perubahan lokal & pull paksa).
    2.  Menyalin `.env.example` ke `.env` lokal.
    3.  Menginstal dependensi Composer & NPM lokal (jika diaktifkan) dan melakukan kompilasi frontend assets (`npm run build`).
    4.  Membangun konfigurasi `.env.prod.<app>` di direktori `env/` secara dinamis dengan meng-generate nilai acak untuk `APP_KEY`, `DB_PASSWORD`, `JWT_SECRET`, dan sepasang *OAuth2 Passport RSA Keys* (khusus IAM server).

### 3️⃣ Mode 3: Gunakan Docker Image (Registry Mode)
*   **Kapan digunakan**: Ketika Anda ingin langsung menjalankan aplikasi menggunakan image Docker yang sudah terkompilasi dan tersedia di registry (seperti Docker Hub atau GHCR) tanpa perlu mengunduh source code-nya secara lokal.
*   **Proses**: Meminta input tag image resmi (contoh: `ghcr.io/juniyasyos/siimut:latest`) dan mencatatnya ke dalam registry lokal `.app-modes` untuk dirujuk oleh docker-compose secara dinamis saat start.

---

## 📂 Struktur Direktori Platform

Platform ini diatur secara modular agar konfigurasi sistem terpisah dengan kode sumber aplikasi:

```
rsch-apps/
├── compose/                         # Konfigurasi Docker Compose Modular
│   ├── base/                        #   Layanan infrastruktur dasar
│   │   ├── infra.yml                #     Aggregator layanan dasar (include all infra)
│   │   ├── network.yml              #     Konfigurasi network global & volume
│   │   ├── web.yml                  #     Nginx Reverse Proxy & SSL mapping
│   │   ├── database.yml             #     MySQL 8.0 & port forwarding
│   │   ├── minio.yml                #     MinIO Object Storage & auto-bucket creation
│   │   ├── phpmyadmin.yml           #     Database Manager (aktif di dev mode saja)
│   │   └── php-base.yml             #     Template service PHP (App/Worker/Scheduler)
│   ├── apps/                        #   Layanan kontainer spesifik per-app
│   │   ├── siimut.yml               #     SIIMUT App, Worker, & Scheduler
│   │   ├── ikp.yml                  #     IKP App, Worker, & Scheduler
│   │   ├── iam.yml                  #     IAM App, Worker, & Scheduler
│   │   └── lms.yml                  #     LMS App & cache volumes
│   ├── profiles/                    #   Override port & environment
│   │   ├── dev.yml                  #     Development port mapping (contoh: port 8010)
│   │   └── prod.yml                 #     Production port mapping (contoh: port 8000)
│   └── build.yml                    #   Manifest kompilasi lokal Docker Image
├── apps/                            # Metadata & Template Konfigurasi Aplikasi
│   ├── <app_name>/                  #   Folder metadata per aplikasi (contoh: siimut)
│   │   ├── app.yml                  #     Spesifikasi port, db, repo, & status daemon
│   │   ├── Dockerfile               #     Dockerfile template rujukan kompilasi
│   │   └── .env.example             #     Template environment khusus produksi
├── docker/                          # Konfigurasi Konteks Kontainer Engine
│   ├── nginx/                       #   Nginx config & virtual host multi-app
│   ├── php/                         #   Global PHP.ini, supervisord, & entrypoint template
│   └── db/                          #   MySQL configuration & init database SQL dump
├── env/                             # Penyimpanan Environment & Secrets (Gitignored)
│   ├── common.env                   #   Environment global (MySQL credentials)
│   ├── dev.env                      #   Konfigurasi IP Host & Port Development
│   ├── prod.env                     #   Konfigurasi IP Host & Port Production
│   └── .env.prod.*                  #   Secrets dinamis hasil kompilasi prepare (gitignored)
├── scripts/                         # Skrip Automasi & Validasi Platform
│   ├── prepare/                     #   Modul helper persiapan (mode_dockerfile/clone/image.sh)
│   ├── health/                      #   Skrip pemeriksaan koneksi/health check per-app
│   └── maintenance/                 #   Skrip diagnostik mandiri (autoload, networking, dll)
├── sources/                         # Folder penyimpanan Source Code aplikasi (gitignored)
├── storage/                         # Volume data persisten MySQL, MinIO & log aplikasi (gitignored)
├── compose.yml                      # Entrypoint utama Docker Compose (meng-extend file modular)
├── rsch                             # Aplikasi CLI utama (Bash executable)
├── repos.csv                        # Registri repositori & branch aplikasi terkelola
└── .app-modes                       # Registri status mode prepare aplikasi (gitignored)
```

Untuk detail penjelasan lengkap tiap komponen direktori, baca: **[docs/STRUCTURE.md](docs/STRUCTURE.md)**.

---

## 🚀 Panduan Memulai Cepat (Quick Start)

Ikuti langkah-langkah ini untuk menyalakan platform secara lengkap dari awal:

### 1. Prasyarat Sistem
Pastikan sistem operasi Anda (Linux/Debian/Ubuntu direkomendasikan) sudah terpasang:
*   **Docker Engine** >= 24.x dan **Docker Compose** v2.
*   **Git** & **OpenSSL** terinstal di host.
*   Port berikut tidak sedang digunakan: `8000`, `8100`, `8200`, `7000`, `9090`, `9091`, `8888`.

*Tips: Gunakan skrip bawaan untuk menginstal Docker Engine di Linux:*
```bash
chmod +x rsch
./rsch scripts/prepare/install-docker.sh
```

### 2. Setup Awal Repository
```bash
# Clone platform manager
git clone <repository-url-platform> rsch-apps
cd rsch-apps

# Buat berkas environment dasar
cp .env.example .env
cp env/dev.env.example env/dev.env
cp env/prod.env.example env/prod.env
```

### 3. Nyalakan Infrastruktur Inti
```bash
./rsch infra up
```
*Ini akan menginisialisasi database MySQL, membuat bucket MinIO S3 otomatis, dan menyalakan reverse proxy.*

### 4. Siapkan Aplikasi (Prepare)
Jalankan perintah berikut untuk mengunduh, mengonfigurasi, dan menyiapkan kredensial rahasia aplikasi secara interaktif:
```bash
./rsch prepare siimut
./rsch prepare iam
./rsch prepare ikp
./rsch prepare lms
```

### 5. Jalankan Platform secara Penuh
```bash
# Menjalankan dalam mode Development (Port terpetakan ke kepala 8xx10)
./rsch up

# ATAU jalankan dalam mode Production (Port terpetakan ke kepala 8xx00)
./rsch up --prod
```

### 6. Verifikasi & Pengujian
```bash
# Periksa status seluruh container
docker compose ps

# Jalankan uji koneksi untuk IAM dan SIIMUT
./rsch health iam
./rsch health siimut
```

---

## 🔍 Sistem Diagnostik & Pemecahan Masalah

Jika Anda mengalami kendala saat deployment, gunakan skrip diagnostik bawaan berikut:

*   **Pemeriksaan Autoload Composer**: `scripts/maintenance/diagnose-autoload.sh`
*   **Pemeriksaan Konfigurasi IAM Server**: `scripts/maintenance/diagnose-iam.sh`
*   **Pemeriksaan Konfigurasi Aset Livewire**: `scripts/maintenance/diagnose-livewire.sh`
*   **Perbaikan Jaringan Docker DNS**: `scripts/maintenance/fix-network.sh`
*   **Pemeriksaan Kesehatan SSO (IAM)**: `./rsch health iam` (mengecek koneksi token API server)
*   **Uji MinIO S3 Integration**: `scripts/health/check-minio.sh`

Panduan lengkap mengenai parameter konfigurasi, panduan operasional harian, dan cara menambahkan aplikasi baru dapat dibaca di: **[docs/USAGE.md](docs/USAGE.md)**.
