# Struktur Proyek `rsch-apps`

Proyek Docker multi-aplikasi untuk deployment empat aplikasi web berbasis Laravel/PHP: **SIIMUT**, **IKP**, **IAM Server**, dan **LMS**.

---

## Tree Structure

```
rsch-apps/
├── .claude/                          # Konfigurasi Claude Code (settings lokal)
├── .dockerignore                     # Ignore rules untuk Docker build context
├── .env.docker                       # Environment variables untuk Docker
├── .env.example / .env.example.new   # Template environment variabel
├── .gitignore
├── VERSION                           # Versi rilis saat ini
│
├── build.sh                          # Script build & push image ke Docker Hub
├── prepare.sh                        # Script clone/pull repo, setup .env, & install dependensi
├── repos.csv                         # Daftar repositori aplikasi (nama, URL git, branch)
├── dc.sh                             # Docker Compose helper shortcut
│
├── docker-compose-build.yml          # Compose untuk proses build image
├── docker-compose.base.yml           # Base compose (service & network definitions)
├── docker-compose-multi-apps.yml     # Compose utama untuk menjalankan semua aplikasi
├── compose.common.yml                # Base service definitions (php-app, worker, scheduler)
│
├── compose.apps/                     # Compose override per-aplikasi
│   ├── siimut.yml                    #   Service definitions khusus SIIMUT
│   ├── ikp.yml                       #   Service definitions khusus IKP
│   ├── iam.yml                       #   Service definitions khusus IAM Server
│   └── lms.yml                       #   Service definitions khusus LMS
│
├── env/                              # Environment files per-aplikasi & per-environment
│   ├── .env.db                       #   Konfigurasi database
│   ├── .env.dev / .env.prod          #   Konfigurasi environment umum
│   ├── .env.siimut / .env.prod.siimut
│   ├── .env.iam / .env.prod.iam
│   ├── .env.ikp
│   ├── .env.lms / .env.prod.lms
│   └── .env.siimut-standalone
│
├── DockerNew/                        # Konfigurasi & asset untuk container Docker
│   ├── db/                           #   Konfigurasi MySQL/MariaDB
│   │   ├── my.cnf                    #     Custom MySQL config
│   │   └── sql/
│   │       └── 00-init-multi-db.sql  #     Inisialisasi multiple database
│   ├── nginx/                        #   Konfigurasi Nginx
│   │   ├── nginx.conf                #     Main Nginx config (global)
│   │   └── nginx-multi-apps.conf     #     Server blocks untuk semua aplikasi
│   ├── php/                          #   Konfigurasi & Dockerfile PHP-FPM
│   │   ├── php.ini                   #     Custom PHP settings
│   │   ├── supervisord.conf          #     Supervisord untuk worker/scheduler
│   │   ├── Dockerfile.*              #     Dockerfile per-aplikasi (registry & production)
│   │   └── entrypoint-*.sh           #     Entrypoint script per-aplikasi
│   └── phpmyadmin/                   #   Konfigurasi phpMyAdmin
│       └── config.inc.php
│
├── site/                             # Source code aplikasi (hasil clone dari prepare.sh)
│   ├── siimut/                       #   SIIMUT - Sistem Informasi Imunisasi
│   ├── ikp/                          #   IKP - Incident Reporting & Pelaporan
│   ├── iam-server/                   #   IAM Server - Authentication & SSO
│   └── lms-app/                      #   LMS - Learning Management System CitraHusada
│
├── ansible/                          # Otomasi deployment server dengan Ansible
│   ├── playbook.yml                  #   Playbook utama deployment
│   ├── inventory.ini                 #   Inventory server target
│   ├── group_vars/                   #   Variable group (contoh: env target)
│   └── templates/                    #   Template konfigurasi
│
├── DEPLOYMENT-GUIDE.md               # Panduan lengkap deployment
├── OPTIMIZATION-GUIDE.sh             # Panduan optimasi performa
│
├── *.sh (utilitas)                   # Script bantuan/utilitas
│   ├── install-docker.sh             #   Instalasi Docker & dependensi
│   ├── fix-network.sh                #   Perbaikan masalah jaringan Docker
│   ├── check-jwt-secrets.sh          #   Validasi JWT secrets
│   ├── check-minio-connections.sh    #   Cek koneksi MinIO (object storage)
│   ├── monitoring-helper.sh          #   Monitoring helper
│   ├── diagnose*.sh                  #   Diagnostik masalah (autoload, Livewire, IAM, signatory)
│   └── entrypoint-livewire-publish.sh#   Publish asset Livewire saat startup
│
└── monitoring-server/                # Proyek terpisah: monitoring server (SNMP)
```

---

## Penjelasan Singkat

### Konsep Utama
Proyek ini adalah **orchestration multi-aplikasi Docker** yang menjalankan empat aplikasi Laravel dalam satu stack, masing-masing dengan service PHP-FPM, worker queue, dan scheduler sendiri, berbagi satu web server Nginx dan database MySQL.

### Empat Aplikasi

| Aplikasi | Direktori | Deskripsi |
|----------|-----------|------------|
| **SIIMUT** | `site/siimut/` | Sistem Informasi Imunisasi - pencatatan & pelaporan imunisasi |
| **IKP** | `site/ikp/` | Incident Reporting & Pelaporan - sistem pelaporan insiden |
| **IAM Server** | `site/iam-server/` | Authentication & SSO Server - manajemen autentikasi terpusat |
| **LMS** | `site/lms-app/` | Learning Management System CitraHusada - platform pembelajaran |

### Alur Kerja

1. **`prepare.sh`** — Membaca `repos.csv`, clone/pull source code ke `site/`, setup file `.env`, dan menginstal dependensi (composer, npm).
2. **`build.sh`** — Build image Docker per-aplikasi (menggunakan `docker-compose-build.yml`), tag, dan push ke Docker Hub.
3. **`docker-compose-multi-apps.yml`** — Menjalankan seluruh stack: web (Nginx), php-app, worker, scheduler untuk setiap aplikasi, database, dan phpMyAdmin.
4. **`ansible/`** — Otomasi deployment ke server production menggunakan Ansible playbook.

### Konfigurasi Kunci
- **`compose.apps/*.yml`** — Override spesifik per-aplikasi (service, volume, environment)
- **`DockerNew/nginx/`** — Nginx reverse proxy dengan server blocks terpisah untuk tiap aplikasi
- **`DockerNew/php/`** — Dockerfile & entrypoint yang berbeda untuk tiap aplikasi (mendukung build registry dan production)
- **`env/`** — File environment terpisah untuk development dan production tiap aplikasi

### Script Utilitas
Berbagai script `.sh` disediakan untuk diagnostik (`diagnose-*.sh`), pengecekan koneksi (`check-*.sh`), perbaikan jaringan (`fix-network.sh`), dan monitoring (`monitoring-helper.sh`).
