# RSCH Application Platform & Deployment Orchestrator

[![Orchestration System](https://img.shields.io/badge/Orchestrator-v2.1.0--modular-blueviolet?style=for-the-badge)](https://github.com/juniyasyos/setup-apps-docker)
[![Docker Support](https://img.shields.io/badge/Docker-Engine%2024.x%2B%20%7C%20Compose%20v2-blue?style=for-the-badge&logo=docker)](https://docs.docker.com/engine/)
[![Laravel Stack](https://img.shields.io/badge/Laravel-PHP%208.4%20%7C%20Alpine-red?style=for-the-badge&logo=laravel)](https://laravel.com/)

Platform Docker multi-aplikasi modular yang dirancang untuk mengotomatisasi siklus hidup (lifecycle) deployment, monitoring, dan manajemen aplikasi internal di lingkungan **Rumah Sakit Citra Husada (RSCH)**. 

Platform ini mengintegrasikan Nginx reverse proxy, basis data terpusat, object storage S3-compatible, SSO server, runner antrean (queues/schedulers), serta mendukung manajemen aplikasi frontend & backend secara simultan.

---

## 🏛️ Arsitektur Sistem (Topologi Jaringan)

Platform ini menggunakan jaringan internal terisolasi (`rsch-apps_default`). Nginx bertindak sebagai gerbang utama (*Reverse Proxy*) yang merutekan domain/host langsung menuju kontainer aplikasi masing-masing, sementara servis *backend* seperti MySQL dan MinIO aman di latar belakang.

```mermaid
graph TD
    Client[Klien / Browser] -->|Port 80/443| Nginx[Nginx Reverse Proxy <br> container: multi-web]
    
    subgraph Jaringan Aplikasi (172.20.0.0/16)
        Nginx -->|siimut.local| SIIMUT[SIIMUT App]
        Nginx -->|iam.local| IAM[IAM Server SSO]
        Nginx -->|ikp.local| IKP[IKP App]
        Nginx -->|lms.local| LMS[LMS App]
        Nginx -->|smsp.local| SMSP[SMSP Backend]
        Nginx -->|port 7250| FESMSP[FE-SMSP React]
        Nginx -->|port 7300| RBV[RBV App]
        
        SIIMUT & IKP & IAM & SMSP & RBV & LMS -->|Koneksi DB| MySQL[(MySQL 8.0 <br> database-service)]
        SIIMUT & IKP & IAM -->|Object Storage S3| MinIO[(MinIO S3 Engine)]
    end
    
    subgraph Layanan Administrator
        MySQL --- phpMyAdmin[phpMyAdmin <br> port: 8888]
    end

    classDef appNode fill:#f9f,stroke:#333,stroke-width:2px;
    classDef dbNode fill:#9f9,stroke:#333,stroke-width:2px;
    classDef proxyNode fill:#bbf,stroke:#333,stroke-width:2px;
    
    class SIIMUT,IKP,IAM,LMS,SMSP,FESMSP,RBV appNode;
    class MySQL,MinIO dbNode;
    class Nginx proxyNode;
```

---

## 📦 Aplikasi Terkelola (Application Matrix)

Terdapat 7 aplikasi (services) inti yang diregistrasikan dan dikelola oleh orchestrator ini:

| Nama Aplikasi | Port Dev | Port Prod | Domain / Host | Repositori Dasar |
| :--- | :---: | :---: | :--- | :--- |
| **SIIMUT** | `8010` | `8000` | `siimut.local` | `si-imut.git` |
| **IAM Server** | `8110` | `8100` | `iam.local` | `auth-server.git` |
| **IKP** | `8210` | `8200` | `ikp.local` | `ikp.git` |
| **LMS** | `7110` | `7100` | `lms.local` | `lms.git` |
| **SMSP** | `-` | `7200` | `smsp.local` | `be-laravel-smartpresence` |
| **FE-SMSP** | `7250` | `7250` | `port 7250` | `fe-react-smartpresence` |
| **RBV** | `-` | `7300` | - | `new-RBV.git` |

> 📖 **Baca Selengkapnya:** Untuk detail spesifik konfigurasi environment, pekerja antrean (queue workers), koneksi SSO, dan spesifikasi per aplikasi, silakan baca **[docs/APPS.md](docs/APPS.md)**.

---

## 🚀 Panduan Memulai Cepat (Quick Start)

Ikuti langkah-langkah ini untuk menyalakan platform secara lengkap dari keadaan kosong:

### 1. Prasyarat Sistem & Setup Awal
Pastikan Docker Engine (>= 24.x) dan Docker Compose v2 terpasang.
```bash
# Clone platform manager
git clone <repository-url-platform> rsch-apps
cd rsch-apps

# Buat berkas environment platform
cp .env.example .env
cp env/dev.env.example env/dev.env
cp env/prod.env.example env/prod.env
```

### 2. Nyalakan Infrastruktur Inti
```bash
./rsch infra up
```
*Mengaktifkan MySQL, Nginx, MinIO S3 bucket, dan volume penyimpanannya.*

### 3. Siapkan Aplikasi (Prepare)
Unduh kode sumber, setup `.env`, generate kredensial (seperti *RSA Keys*, JWT Secret), dan install dependensi secara otomatis:
```bash
# Siapkan satu per satu
./rsch prepare siimut
./rsch prepare iam
./rsch prepare ikp
./rsch prepare lms
./rsch prepare smsp
./rsch prepare fe-smsp
./rsch prepare rbv

# ATAU siapkan sekaligus secara sekuensial
./rsch prepare all
```

### 4. Jalankan Platform secara Penuh
```bash
# Menjalankan dalam mode Development (Mapping ke Port Dev)
./rsch up

# ATAU jalankan dalam mode Production (Mapping ke Port Prod, tanpa Debug)
./rsch up --prod
```

---

## 📚 Dokumentasi Lebih Lanjut

Kami telah menyusun dokumentasi komprehensif (deep-dive) di direktori `docs/` untuk keperluan operasi harian:

1. 📂 **[Struktur Arsitektur & Direktori](docs/STRUCTURE.md)**: Membedah konfigurasi low-level di folder `compose/`, `docker/`, skrip otomasi (`scripts/`), dan manajemen *environment secrets*.
2. 🗂️ **[Spesifikasi Matrix Aplikasi](docs/APPS.md)**: Detail spesifik dari konfigurasi, dependensi layanan (SSO, MinIO, Queue), dan rute setiap aplikasi.
3. 🛠️ **[Panduan Operasional CLI & Troubleshooting](docs/USAGE.md)**: Referensi lengkap command `./rsch`, diagnostik, dan panduan men-scaffold (menambahkan) aplikasi baru ke dalam platform.

---
**RSCH DevOps Team** | *Automated Application Manager v2.1.0*
