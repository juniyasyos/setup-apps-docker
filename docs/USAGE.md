# Panduan Penggunaan — RSCH Application Platform

> **Platform**: Docker multi-aplikasi untuk deployment dan manajemen aplikasi Laravel secara modular.
> **CLI**: `./rsch` — satu entrypoint untuk semua operasi.

---

## Daftar Isi

1. [Arsitektur](#arsitektur)
2. [Prasyarat](#prasyarat)
3. [Setup Awal](#setup-awal)
4. [CLI Reference](#cli-reference)
5. [Manajemen Aplikasi](#manajemen-aplikasi)
6. [Environment & Secrets](#environment--secrets)
7. [Build & Push Image](#build--push-image)
8. [Troubleshooting](#troubleshooting)
9. [Referensi File](#referensi-file)

---

## Arsitektur

```
rsch-apps/
│
├── compose/                        # Definisi Docker Compose
│   ├── base/                       #   Service infrastruktur + web
│   │   ├── infra.yml               #     Aggregator infrastruktur
│   │   ├── network.yml             #     Network + volume global
│   │   ├── web.yml                 #     Nginx reverse proxy
│   │   ├── database.yml            #     MySQL 8.0
│   │   ├── minio.yml               #     Object Storage (S3)
│   │   ├── phpmyadmin.yml          #     Database admin panel (profile dev)
│   │   └── php-base.yml            #     Template PHP (app/worker/scheduler)
│   ├── apps/                       #   Service aplikasi per-app
│   │   ├── siimut.yml
│   │   ├── ikp.yml
│   │   ├── iam.yml
│   │   └── lms.yml
│   ├── profiles/                   #   Environment override
│   │   ├── dev.yml
│   │   └── prod.yml
│   └── build.yml                   #   Build manifest (Dockerfile)
│
├── apps/                           # Definisi aplikasi
│   ├── siimut/                     #   SIIMUT
│   ├── ikp/                        #   IKP
│   ├── iam/                        #   IAM Server
│   └── lms/                        #   LMS
│
├── docker/                         # Konfigurasi container
│   ├── nginx/                      #   Konfigurasi Nginx
│   ├── php/                        #   PHP Dockerfile + entrypoint
│   └── db/                         #   MySQL config + SQL init
│
├── env/                            # Environment files
│   ├── common.env                  #   Variabel bersama
│   ├── dev.env                     #   Development vars
│   └── prod.env                    #   Production vars
│
├── scripts/                        # Automation
│   ├── prepare/                    #   Persiapan app
│   ├── build/                      #   Build tools
│   ├── deploy/                     #   Deployment helpers
│   ├── health/                     #   Health checks
│   ├── maintenance/                #   Diagnostics
│   └── generate/                   #   Code gen
│
├── compose.yml                     # Manifest utama (semua service)
├── .env.example                    # Template env
└── rsch                            # CLI entrypoint
```

### Alur Service

```
                        ┌──────────────┐
                        │    Nginx     │  web (compose.yml)
                        │  (reverse    │
                        │   proxy)     │
                        └──────┬───────┘
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
    ┌─────▼──────┐      ┌─────▼──────┐      ┌─────▼──────┐
    │  app-      │      │  app-      │      │  app-      │
    │  siimut    │      │  ikp       │      │  iam       │
    │(:8000)     │      │(:8200)     │      │(:8100)     │
    └─────┬──────┘      └─────┬──────┘      └─────┬──────┘
          │                    │                    │
    ┌─────▼──────┐      ┌─────▼──────┐      ┌─────▼──────┐
    │ queue-     │      │ queue-     │      │ queue-     │
    │ siimut     │      │ ikp        │      │ iam        │
    └────────────┘      └────────────┘      └────────────┘
    ┌────────────┐      ┌────────────┐      ┌────────────┐
    │ scheduler- │      │ scheduler- │      │ scheduler- │
    │ siimut     │      │ ikp        │      │ iam        │
    └────────────┘      └────────────┘      └────────────┘

    ── Base Infrastructure ──────────────────────────────
    ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌────────┐
    │  MySQL   │  │  MinIO   │  │phpMyAdmin│  │Portainer│
    │(:3306)   │  │(:9090)   │  │(:8888)   │  │(:9000)  │
    └──────────┘  └──────────┘  └──────────┘  └────────┘

    Network: rsch-apps_default (172.20.0.0/16)
```

### Penamaan Resource

| Resource | Format | Contoh |
|---|---|---|
| Container app | `{app}-app` | `siimut-app`, `ikp-app` |
| Container queue | `{app}-queue` | `siimut-queue` |
| Container scheduler | `{app}-scheduler` | `siimut-scheduler` |
| Volume storage | `{app}_storage` | `siimut_storage` |
| Volume public | `{app}_public` | `siimut_public` |
| Volume bootstrap cache | `{app}_bootstrap_cache` | `siimut_bootstrap_cache` |

---

## Prasyarat

| Requirement | Minimal | Catatan |
|---|---|---|
| **Docker Engine** | 24.x+ | Pakai Docker Compose v2 bawaan |
| **Git** | 2.x | Untuk cloning repository |
| **OpenSSL** | 1.1+ | Untuk generate secrets |
| **RAM** | 8 GB (dev) / 16 GB (prod) | Semua service jalan bersamaan |
| **Disk** | 20 GB+ | Untuk image, volume, dan source code |
| **Ports** | 8000, 8100, 8200, 7000, 9090, 9091, 8888 | Pastikan tidak konflik |

### Install Docker

```bash
# Via script yang disediakan
./rsch scripts/prepare/install-docker.sh

# Atau manual — lihat https://docs.docker.com/engine/install/
```

---

## Setup Awal

### 1. Clone Project

```bash
git clone <repo-url> rsch-apps
cd rsch-apps
```

### 2. Setup Environment

```bash
# Salin template .env
cp .env.example .env

# Setup environment files
cp env/dev.env.example env/dev.env      # Development
cp env/prod.env.example env/prod.env    # Production
```

### 3. Start Infrastructure

```bash
# Jalankan semua service infrastruktur (MySQL, MinIO, phpMyAdmin)
./rsch infra up
```

Perintah ini menjalankan `docker compose -f compose/base/infra.yml up -d` yang akan:

1. Membuat network `rsch-apps_default`
2. Menjalankan MySQL (`database-service`)
3. Menjalankan MinIO + membuat bucket (siimut, ikp, data-center)
4. phpMyAdmin (dengan profile `dev` — aktif otomatis)

> phpMyAdmin hanya aktif dengan profile `dev`. Untuk production via compose.yml root, profile tidak digunakan.

### 4. Siapkan Aplikasi

```bash
# Clone repo, setup .env, install dependencies
./rsch prepare siimut
./rsch prepare ikp
./rsch prepare iam
./rsch prepare lms

# Atau semua sekaligus
./rsch prepare all
```

Proses `prepare` melakukan:

| Fase | Deskripsi | Lokasi Output |
|---|---|---|
| **Git** | Clone repository ke `sources/` | `sources/{app_dir}/` |
| **Env** | Copy `.env.example` ke `.env` | `sources/{app_dir}/.env` |
| **Deps** | Install composer + npm dependencies | Dalam `sources/{app_dir}/` |
| **Prod Env** | Generate production env dengan secrets | `env/.env.prod.{app}` |

> **IAM Server**: Tidak copy `.env.example` langsung — konfigurasi dibaca dari `apps/iam/.env.example`.

### 5. Jalankan Semua Service

```bash
# Development mode (default ports: 8010, 8210, 8110, 7000)
./rsch up

# Production mode (default ports: 8000, 8200, 8100, 7000)
./rsch up --prod
```

### 6. Verifikasi

```bash
# Cek semua container berjalan
docker compose ps

# Health check per aplikasi
./rsch health siimut
./rsch health ikp

# Lihat logs
./rsch logs siimut
```

Akses via browser:

| App | Dev URL | Prod URL |
|---|---|---|
| **SIIMUT** | http://192.168.1.9:8010 | http://192.168.1.4:8000 |
| **IKP** | http://192.168.1.9:8210 | http://192.168.1.4:8200 |
| **IAM** | http://192.168.1.9:8110 | http://192.168.1.4:8100 |
| **LMS** | http://192.168.1.9:7000 | http://192.168.1.4:7000 |
| **MinIO Console** | http://localhost:9091 | http://localhost:9091 |
| **phpMyAdmin** | http://localhost:8888 | — |

> Default IP: `192.168.1.9` (dev), `192.168.1.4` (prod). Ubah di `env/dev.env` / `env/prod.env`.

---

## CLI Reference

### `./rsch prepare <app>`

Siapkan aplikasi untuk deployment: clone repo, setup env, install dependencies.

```bash
# Siapkan satu aplikasi
./rsch prepare siimut

# Siapkan semua aplikasi
./rsch prepare all

# Lihat daftar aplikasi tersedia
./rsch list
```

Options:

| Flag | Fungsi |
|---|---|
| `--no-deps` | Skip install composer & npm dependencies |

### `./rsch build <app>`

Build Docker image untuk aplikasi.

```bash
# Build image siimut
./rsch build siimut

# Build + push ke Docker Hub
./rsch build siimut push

# Build semua aplikasi + push
./rsch build all push
```

Lihat juga: [Build & Push Image](#build--push-image)

### `./rsch up [--dev|--prod]`

Mulai semua service.

```bash
# Development (default)
./rsch up              # setara --dev

# Production
./rsch up --prod
```

Apa yang dijalankan:

| Service | Sumber |
|---|---|
| Nginx | `compose.yml` — service `web` |
| App Services | `compose.yml` — extends `compose/apps/*.yml` |
| Queue Workers | `compose.yml` — extends `compose/apps/*.yml` |
| Schedulers | `compose.yml` — extends `compose/apps/*.yml` |

### `./rsch down [--dev|--prod]`

Hentikan semua service (volume tetap aman).

```bash
./rsch down
```

> Aman: `down` tidak pernah jalan dengan `--volumes`. Volume persisten dipertahankan.

### `./rsch restart <app>`

Restart service untuk satu aplikasi (app + queue + scheduler).

```bash
./rsch restart siimut
```

### `./rsch logs <app>`

Lihat logs untuk service aplikasi.

```bash
# Stream logs siimut (app + queue — 100 baris terakhir)
./rsch logs siimut
```

### `./rsch health <app>`

Jalankan health check untuk aplikasi.

```bash
./rsch health siimut
```

Jika ada script spesifik di `scripts/health/check-{app}.sh`, akan dijalankan. Jika tidak, fallback ke `docker compose ps`.

### `./rsch infra up|down|restart`

Manajemen service infrastruktur saja (tanpa aplikasi).

```bash
./rsch infra up         # Start MySQL, MinIO, phpMyAdmin
./rsch infra down       # Stop semua infra
./rsch infra restart    # Restart semua infra
```

### `./rsch list`

Tampilkan daftar aplikasi yang tersedia.

---

## Environment & Secrets

### Struktur Environment

```
env/
├── common.env       # Variabel bersama untuk semua service (MySQL root creds)
├── dev.env          # Development: HOST_IP, port mapping
└── prod.env         # Production: HOST_IP, port mapping
```

### Variabel Penting

#### `env/common.env`

| Variabel | Default | Keterangan |
|---|---|---|
| `MYSQL_ROOT_PASSWORD` | `rootpass123` | Password root MySQL |
| `MYSQL_RANDOM_ROOT_PASSWORD` | `no` | Nonaktifkan random password |
| `MYSQL_CHARSET` | `utf8mb4` | Character set |
| `MYSQL_COLLATION` | `utf8mb4_unicode_ci` | Collation |

#### `env/dev.env`

| Variabel | Default | Keterangan |
|---|---|---|
| `HOST_IP` | `192.168.1.9` | IP host untuk development |
| `SIIMUT_HOST_PORT` | `8010` | Port SIIMUT |
| `IKP_HOST_PORT` | `8210` | Port IKP |
| `IAM_HOST_PORT` | `8110` | Port IAM |
| `LMS_HOST_PORT` | `7000` | Port LMS |

#### `env/prod.env`

| Variabel | Default | Keterangan |
|---|---|---|
| `HOST_IP` | `192.168.1.4` | IP host production |
| `SIIMUT_HOST_PORT` | `8000` | Port SIIMUT |
| `IKP_HOST_PORT` | `8200` | Port IKP |
| `IAM_HOST_PORT` | `8100` | Port IAM |

### Production Secrets

Secrets di-generate otomatis saat `./rsch prepare`:

```
env/.env.prod.siimut    # APP_KEY, DB_PASSWORD, JWT_SECRET
env/.env.prod.iam       # APP_KEY, JWT_SECRET, Passport RSA Keys
env/.env.prod.lms       # APP_KEY, DB_PASSWORD
```

> **Security Note**: File `.env.prod.*` masuk `.gitignore`. Jangan pernah commit secrets!

#### IAM Passport Keys

IAM Server butuh RSA key pair untuk Laravel Passport. Key di-generate otomatis di fase `prepare` dan disimpan di `env/.env.prod.iam`.

**Jika Passport key bermasalah**:

```bash
# Regenerate di dalam container
docker exec -it iam-app php artisan passport:keys --force
```

### Konfigurasi Aplikasi per-App

Setiap aplikasi punya konfigurasi di `apps/{name}/`:

```
apps/siimut/
├── app.yml             # Metadata aplikasi (nama, repo, branch, port, database)
├── Dockerfile          # Build image
└── .env.example        # Template environment
```

#### Format `app.yml`

```yaml
name: siimut
repo: https://github.com/juniyasyos/si-imut.git
branch: main
source_dir: siimut
image: juniyasyos/siimut
version: v2.0.0
port: 8000
domain: siimut.local
database: siimut_db
db_user: siimut_user
queue: true
scheduler: true
php_version: "8.4"
description: SIIMUT - Sistem Informasi Imunisasi
```

---

## Build & Push Image

### Alur Build

```
Source Code → Dockerfile → Docker Image → Tag → Push ke Registry
(sources/)    (apps/*/)    (local)       (v*)   (Docker Hub)
```

### Build Image

```bash
# Build satu aplikasi
docker compose -f compose/build.yml build siimut

# Atau via script
./scripts/build.sh siimut
./scripts/build.sh siimut push    # Build + Push ke Docker Hub
./scripts/build.sh all push       # Build + Push semua aplikasi
```

### Set Version

```bash
# Via file (default)
echo "v2.0.0" > VERSION

# Via environment variable (override)
SIIMUT_VERSION=v2.1.0 ./scripts/build.sh siimut push
```

Per-service version override:

| Variable | Applies to | Default |
|---|---|---|
| `SIIMUT_VERSION` | SIIMUT | `v2.0.0` |
| `IKP_VERSION` | IKP | `v1.0.0` |
| `IAM_VERSION` | IAM Server | `v1.0.0` |
| `LMS_VERSION` | LMS | `v1.0.0` |

### Build Configuration

`compose/build.yml` berisi semua konfigurasi build:

```yaml
services:
  siimut:
    build:
      context: .
      dockerfile: apps/siimut/Dockerfile
      args:
        APP_DIR: siimut
        DB_HOST: database-service
        # ... build args untuk optimasi image
    image: siimut:v2.0.0
```

### Push to Docker Hub

```bash
# Login dulu
docker login

# Build + Push
DOCKER_HUB_USER=juniyasyos ./scripts/build.sh siimut push
```

Images di-tag sebagai:
- `juniyasyos/siimut:v2.0.0` (versioned)
- `juniyasyos/siimut:latest` (latest)

---

## Troubleshooting

### 1. Container Restart Loop

```bash
# Cek logs
docker compose logs app-siimut --tail=50

# Cek health
docker compose ps app-siimut

# Restart
./rsch restart siimut
```

### 2. Database Connection Error

```bash
# Pastikan database-service berjalan
docker compose -f compose/base/infra.yml ps

# Cek health
docker compose -f compose/base/infra.yml exec db mysqladmin ping -uroot -prootpass123

# Cek network
docker network inspect rsch-apps_default
```

### 3. MinIO Bucket Tidak Terbuat

```bash
# Jalankan ulang minio-init
docker compose -f compose/base/infra.yml start minio-init

# Atau manual via mc
docker exec -it minio mc ls myminio/
```

### 4. Permission Issues

```bash
# Cek permission volume
docker exec siimut-app ls -la /var/www/siimut/storage

# Fix permission
docker exec siimut-app chmod -R 775 /var/www/siimut/storage
docker exec siimut-app chown -R www-data:www-data /var/www/siimut/storage
```

### 5. Cache & Config Clear

```bash
# Clear Laravel cache
docker exec siimut-app php artisan optimize:clear

# Clear route & config cache
docker exec siimut-app php artisan config:clear
docker exec siimut-app php artisan route:clear
docker exec siimut-app php artisan view:clear
```

### 6. Diagnostik Tools

Project menyediakan script diagnostik:

```bash
# Diagnostik umum
./scripts/maintenance/diagnose.sh

# Diagnostik spesifik
./scripts/maintenance/diagnose-autoload.sh     # Composer autoload
./scripts/maintenance/diagnose-iam.sh           # IAM Server
./scripts/maintenance/diagnose-livewire.sh      # Livewire
./scripts/maintenance/diagnose-signatory.sh     # Signatory

# Diagnostik network
./scripts/maintenance/fix-network.sh

# Health check
./scripts/health/check-jwt.sh                   # JWT validation
./scripts/health/check-minio.sh                 # MinIO connectivity
```

---

## Referensi File

### Docker Compose Files

| File | Fungsi | Cara Pakai |
|---|---|---|
| `compose.yml` | Main manifest — semua service aplikasi | `./rsch up` |
| `compose/base/infra.yml` | Aggregator infrastruktur | `./rsch infra up` |
| `compose/base/network.yml` | Network + volume global | `include` oleh infra.yml |
| `compose/base/database.yml` | MySQL service | `include` oleh infra.yml |
| `compose/base/minio.yml` | MinIO service | `include` oleh infra.yml |
| `compose/base/phpmyadmin.yml` | phpMyAdmin (profile dev) | `include` oleh infra.yml |
| `compose/base/php-base.yml` | Template PHP app/worker/scheduler | `extends` oleh apps/*.yml |
| `compose/apps/{app}.yml` | Service per-aplikasi | `extends` oleh compose.yml |
| `compose/profiles/dev.yml` | Development override | `-f compose.yml -f profiles/dev.yml` |
| `compose/profiles/prod.yml` | Production override | `-f compose.yml -f profiles/prod.yml` |
| `compose/build.yml` | Build manifest | `docker compose -f compose/build.yml build` |

### Scripts

| Script | Fungsi |
|---|---|
| `scripts/prepare.sh` | Clone, setup env, install dependencies |
| `scripts/build.sh` | Build & push Docker image |
| `scripts/deploy.sh` | Start/stop stack (dipanggil oleh rsch CLI) |

### Docker Config

| Path | Isi |
|---|---|
| `docker/nginx/nginx.conf` | Konfigurasi utama Nginx |
| `docker/nginx/nginx-multi-apps.conf` | Virtual host multi-app |
| `docker/php/Dockerfile.production` | PHP production Dockerfile |
| `docker/php/entrypoint.sh` | Entrypoint dev |
| `docker/php/entrypoint-prod.sh` | Entrypoint production |
| `docker/php/php.ini` | PHP configuration |
| `docker/php/supervisord.conf` | Supervisor untuk queue/scheduler |
| `docker/db/my.cnf` | MySQL configuration |
| `docker/db/sql/` | SQL initialization scripts |

---

## Menambah Aplikasi Baru

1. Buat direktori di `apps/{nama}/`
2. Isi dengan:
   - `app.yml` — metadata aplikasi
   - `Dockerfile` — build instruction
   - `.env.example` — template environment
3. Tambahkan ke `compose/apps/{nama}.yml` (extends php-base)
4. Tambahkan ke `compose.yml` (extends service)
5. Tambah konfigurasi Nginx di `docker/nginx/`
6. Tambah volume di `compose.yml`
7. Tambah ke `repos.csv`
8. Jalankan `./rsch prepare {nama}`

Contoh template app.yml:

```yaml
name: myapp
repo: https://github.com/org/myapp.git
branch: main
source_dir: myapp
image: juniyasyos/myapp
version: v1.0.0
port: 9000
domain: myapp.local
database: myapp_db
db_user: myapp_user
queue: true
scheduler: false
php_version: "8.4"
description: Aplikasi Baru
```
