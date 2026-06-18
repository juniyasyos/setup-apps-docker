# Detailed Project Structure & Architecture Guide — RSCH Application Platform

This document provides a deep-dive architectural map of the **RSCH Application Platform**. It details every file, directory, named volume, network interface, port allocation, and structural design decision.

---

## 📂 Directory Layout (Root Overview)

Below is the complete tree representing the workspace organization.

```text
rsch-apps/
├── apps/                            # Application metadata and runtime base environments
├── compose/                         # Docker Compose modular configuration files
├── docker/                          # Low-level service and container runtimes configs
├── env/                             # Environment variables & runtime secrets (Gitignored)
├── scripts/                         # Command utilities, health checkers, & maintenance scripts
├── site/                         # Raw application source code directories (Gitignored)
├── storage/                         # Local mount directories for persistent database/storage files
│
├── compose.yml                      # Main Compose aggregator manifest
├── rsch                             # Platform Orchestration CLI entrypoint
├── repos.csv                        # Global repository configuration registry
├── .env.example                     # Reference template for top-level platform env variables
├── .app-modes                       # Internal registry for chosen app prepare modes (Gitignored)
│
├── README.md                        # Quick-start and main systems overview
└── docs/                            # Deep-dive platform documentation
    ├── APPS.md                      # Detailed registry and setup of each application
    ├── USAGE.md                     # Exhaustive runtime and operations guide
    └── STRUCTURE.md                 # This file
```

---

## 📋 Application Registry & Metadata (`apps/`)

Setiap aplikasi memiliki direktorinya sendiri di dalam folder `apps/`. Folder ini berfungsi sebagai titik referensi bagi skrip otomasi.
Contoh struktur `apps/siimut/`:
*   **`app.yml`**: Berisi definisi nama, URL repository, target branch, penamaan image, spesifikasi port (host/internal), routing nginx, koneksi database, dan apakah aplikasi tersebut menggunakan antrean/scheduler.
*   **`Dockerfile`**: Resep instruksi build Docker untuk mengompilasi image production khusus aplikasi tersebut (biasanya berbasis template `docker/php/Dockerfile.production`).
*   **`.env.example`**: Referensi template *environment variables* yang wajib disuplai ke dalam aplikasi saat dijalankan.

Aplikasi yang saat ini berada di folder `apps/`: `siimut`, `iam`, `ikp`, `lms`, `smsp`, `fe-smsp`, `rbv`. Detail masing-masing baca di **[docs/APPS.md](APPS.md)**.

---

## 🐳 Modular Compose Architecture (`compose/`)

Platform menghindari satu file `docker-compose.yml` monolitik yang berukuran masif dengan memecahnya ke dalam modul menggunakan fitur `include` dan `extends` (Docker Compose v2).

```text
compose/
├── base/                            # Layanan inti infrastruktur
│   ├── infra.yml                    # Aggregator layanan dasar (memuat semua base infra)
│   ├── network.yml                  # Deklarasi subnet (172.20.0.0/16) dan konfigurasi volume
│   ├── web.yml                      # Nginx Reverse Proxy & SSL mapping utama
│   ├── database.yml                 # Layanan MySQL 8.0 (database-service)
│   ├── minio.yml                    # MinIO S3 object storage server & auto-bucket creation job
│   ├── phpmyadmin.yml               # GUI Manajemen Database (Aktif di Dev)
│   └── php-base.yml                 # Template utama service PHP (App, Queue Worker, Scheduler)
│
├── apps/                            # Spesifikasi Layanan Per-Aplikasi (Hasil turunan dari base)
│   ├── siimut.yml                   # SIIMUT containers (App, Daemon, Cron Scheduler)
│   ├── iam.yml                      # SSO Server containers
│   ├── ikp.yml                      # IKP containers
│   ├── lms.yml                      # LMS containers
│   ├── smsp.yml                     # SMSP Backend containers
│   ├── fe-smsp.yml                  # SMSP Frontend containers (React/Vite)
│   └── rbv.yml                      # RBV containers
│
├── profiles/                        # Override konfigurasi port mapping
│   ├── dev.yml                      # Menghubungkan aplikasi ke host port dev (contoh 8010)
│   └── prod.yml                     # Menghubungkan aplikasi ke host port prod (contoh 8000)
│
└── build.yml                        # Manifest instruksi cara men-compile seluruh image lokal
```

---

## ⚙️ Container Engine Configurations (`docker/`)

Konfigurasi level *low* yang memodifikasi sifat sistem operasi dan komponen di dalam kontainer.

*   **`docker/nginx/`**:
    *   `nginx.conf`: Konfigurasi Nginx dasar global (performa, timeout, gzip compression).
    *   `nginx-multi-apps.conf`: File penentu rute (*Virtual Host*). Menentukan ke port internal mana subdomain diarahkan via `proxy_pass` atau `fastcgi_pass`.
*   **`docker/php/`**:
    *   `entrypoint.sh`: Titik awal kontainer PHP. Script ini memastikan cache routing dibersihkan, memverifikasi ketersediaan database MySQL menggunakan soket, lalu memulai proses FPM.
    *   `entrypoint-iam.sh`: Entrypoint unik khusus IAM server untuk membuat file Passport RSA Public/Private Key saat startup.
    *   `php.ini`: Hardened production settings (OPcache JIT diaktifkan, pengaturan memori).
    *   `supervisord.conf`: Konfigurasi untuk menjalankan *queue worker* secara presisten sebagai daemon.
*   **`docker/db/`**:
    *   `my.cnf`: Tuning parameter InnoDB MySQL dan pengaturan batasan memori.
    *   `sql/`: Skrip `init` yang berjalan otomatis jika basis data MySQL masih kosong di awal pembuatan kontainer.

---

## 🐍 Automasi & Utilitas Sistem (`scripts/`)

Skrip di dalam direktori `scripts/` digunakan sebagai ekstensi *backend* dari perintah CLI `./rsch`.

```text
scripts/
├── prepare.sh                       # Core unified orchestration logic (runs mode selection)
├── build.sh                         # Automated image compiling and tagging
├── deploy.sh                        # Docker compose interface (penerjemah opsi run)
├── scaffold.sh                      # Boilerplate generator untuk aplikasi baru
│
├── prepare/                         # Modularity adapters untuk './rsch prepare'
│   ├── mode_dockerfile.sh           #   [Mode 1] Meng-generate Dockerfile PHP Alpine
│   ├── mode_clone.sh                #   [Mode 2] Clone kode, install composer/npm, generate config
│   ├── mode_image.sh                #   [Mode 3] Mendaftarkan remote Docker registry image
│   └── install-docker.sh            #   Auto-installer bash untuk Ubuntu/Debian host
│
├── health/                          # Penguji interaksi layanan (./rsch health <app>)
│   ├── check-iam.sh                 #   Validasi SSO server API & token
│   └── check-minio.sh               #   Validasi MinIO S3 dan pembuatan Bucket
│
├── maintenance/                     # Troubleshooting tools
│   ├── diagnose.sh                  #   Pemeriksa konektivitas jaringan secara umum
│   ├── diagnose-autoload.sh         #   Pemeriksa masalah class dumping di Composer
│   ├── diagnose-iam.sh              #   Pemeriksa setup OAuth2 client credentials
│   ├── diagnose-livewire.sh         #   Pemeriksa rendering CDN Livewire
│   ├── diagnose-signatory.sh        #   Pemeriksa status enkripsi
│   └── fix-network.sh               #   Script tanggap darurat mereset jembatan DNS Docker
│
└── .scaffold_py/                    # Python parser untuk injeksi dinamis dari ./rsch scaffold
    ├── insert_build.py, insert_compose.py, insert_web.py
```

---

## 🔒 Storage, site, & Variables Segregation

### `site/` (Gitignored)
Folder ini menampung seluruh *source code* (kode sumber) aplikasi hasil pull dari Git (contoh: `site/siimut`, `site/iam-server`). Folder ini akan langsung di-*mount* ke dalam kontainer jika aplikasi berjalan pada environment lokal, memastikan setiap *save* file akan langsung merefresh kontainer.

### `storage/` (Gitignored)
Data vital aplikasi disimpan secara persisten di folder host ini, sehingga file fisik tidak akan hilang walaupun seluruh Docker container dan image dihapus (contoh: `./rsch down` atau `./rsch infra down`).
*   `storage/mysql/`: Database state.
*   `storage/minio/`: Dokumen dan media yang diupload ke S3 Storage lokal.
*   `storage/logs/`: Menyimpan output nginx dan laravel error log terpusat.

### `env/` (Gitignored)
Mengisolasi data sensitif seperti password dari repositori Git:
*   `common.env`: Variabel awam (Root DB config).
*   `dev.env` & `prod.env`: Pemetaan target alamat Host IP.
*   `.env.prod.<app>`: Kredensial spesifik production per aplikasi (misal `DB_PASSWORD` dan enkripsi `APP_KEY`) yang akan diisi secara acak oleh skrip mode prepare secara aman.

---

## 🌐 Network Topography & Volume Map

*   **Network Name**: `rsch-apps_default`
*   **Subnet CIDR**: `172.20.0.0/16`

Semua layanan tidak terbuka keluar secara langsung (Isolated internal routing), KECUALI Nginx Proxy. Skrip routing di dalam proxy `nginx-multi-apps.conf` yang mengurusi translasi ke port fastCGI (`9000`) dari setiap kontainer aplikasi.
