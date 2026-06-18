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
flowchart TB
    Client("🌐 Klien / Browser")
    
    subgraph Proxy["Reverse Proxy Layer"]
        Nginx{"Nginx Reverse Proxy<br/>(multi-web)"}
    end

    subgraph Network["Docker Bridge Network (rsch-apps_default - 172.20.0.0/16)"]
        
        subgraph Apps["🚀 Application Services"]
            direction TB
            IAM["🛡️ IAM Server SSO<br/>(iam.local)"]
            SIIMUT["🏥 SIIMUT App<br/>(siimut.local)"]
            IKP["📝 IKP App<br/>(ikp.local)"]
            LMS["📚 LMS App<br/>(lms.local)"]
            RBV["🏥 RBV App<br/>(port 7300)"]
            
            subgraph SMSP_Stack["SMSP Stack"]
                FESMSP["💻 FE-SMSP React<br/>(port 7250)"]
                SMSP["⚙️ SMSP Backend<br/>(smsp.local)"]
            end
        end

        subgraph Background["⚙️ Background Tasks"]
            Queue["🔄 Queue Workers"]
            Cron["⏱️ Schedulers"]
        end

        subgraph Infra["🗄️ Core Infrastructure"]
            direction LR
            MySQL[("🐬 MySQL 8.0<br/>(database-service)")]
            MinIO[("🪣 MinIO Storage<br/>(S3 Engine)")]
        end
    end

    subgraph Admin["🛠️ Layanan Administrator"]
        PMA["⚙️ phpMyAdmin<br/>(Port: 8888)"]
    end

    %% Routing / Ingress
    Client == "HTTP/HTTPS<br/>Port 80/443" ==> Nginx
    
    Nginx -.->|"Routing HTTP/Proxy"| SIIMUT
    Nginx -.-> IKP
    Nginx -.-> LMS
    Nginx -.-> RBV
    Nginx -.-> IAM
    Nginx -.-> SMSP
    Nginx -.-> FESMSP

    %% Frontend to Backend API
    FESMSP -.->|"API Calls"| SMSP

    %% SSO Connections (IAM)
    SIIMUT & IKP & LMS -.->|"SSO Auth"| IAM

    %% Database Connections
    SIIMUT & IKP & LMS & RBV & SMSP & IAM ===>|"Port 3306"| MySQL
    
    %% S3 Connections
    SIIMUT & IKP & IAM ===>|"Port 9000 (S3 API)"| MinIO
    
    %% Background tasks
    Queue & Cron -.- Apps
    Queue & Cron -.- MySQL
    
    %% Admin Panels
    PMA ---|"Manage DB"| MySQL

    %% Styling
    classDef proxyLayer fill:#1f2937,stroke:#4ade80,stroke-width:3px,color:#fff;
    classDef appNode fill:#3b82f6,stroke:#1e40af,stroke-width:2px,color:#fff;
    classDef dbNode fill:#10b981,stroke:#047857,stroke-width:2px,color:#fff;
    classDef ssoNode fill:#8b5cf6,stroke:#5b21b6,stroke-width:3px,color:#fff;
    classDef bgNode fill:#f59e0b,stroke:#b45309,stroke-width:2px,color:#fff;
    classDef adminNode fill:#ef4444,stroke:#b91c1c,stroke-width:2px,color:#fff;

    class Nginx proxyLayer;
    class SIIMUT,IKP,LMS,SMSP,FESMSP,RBV appNode;
    class IAM ssoNode;
    class MySQL,MinIO dbNode;
    class Queue,Cron bgNode;
    class PMA adminNode;
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
