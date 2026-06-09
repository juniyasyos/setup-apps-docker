# Refactor & Upgrade Plan - RSCH Multi Application Docker Platform

## Tujuan Refactor

Menyederhanakan struktur project Docker multi-aplikasi agar:

* Lebih mudah dipahami developer baru.
* Lebih mudah melakukan maintenance.
* Lebih mudah menambah aplikasi baru.
* Mengurangi duplikasi konfigurasi.
* Memisahkan infrastructure dan application concerns.
* Mendukung otomatisasi penuh melalui satu command CLI.
* Menjadi platform deployment yang modular dan scalable.

Target akhirnya adalah menjadikan repository ini sebagai:

> "Application Platform & Deployment Orchestrator"

bukan sekadar kumpulan Docker Compose dan source code aplikasi.

---

# Masalah Struktur Saat Ini

## Infrastructure dan Application Tercampur

Saat ini:

* Docker
* Nginx
* MySQL
* MinIO
* phpMyAdmin
* Source code aplikasi
* Build process
* Deployment automation
* Troubleshooting scripts

berada dalam satu level organisasi yang kurang jelas.

Akibatnya:

* Sulit mencari konfigurasi tertentu.
* Penambahan aplikasi baru membutuhkan banyak perubahan file.
* Root repository menjadi terlalu ramai.
* Sulit melakukan standarisasi.

---

## Terlalu Banyak Compose Layer

Saat ini terdapat:

* docker-compose.base.yml
* docker-compose-build.yml
* docker-compose-multi-apps.yml
* compose.common.yml
* compose.apps/*.yml

Hubungan antar file sulit dipahami.

Developer perlu memahami banyak layer sebelum mengetahui service yang sebenarnya dijalankan.

---

## Source Code Aplikasi Menjadi Bagian Struktur Utama

Folder:

site/
├── siimut
├── ikp
├── iam-server
└── lms-app

menyebabkan repository orchestration menjadi semakin besar.

Repository orchestration seharusnya fokus pada deployment dan runtime, bukan menyimpan struktur aplikasi sebagai bagian inti sistem.

---

## Docker Configuration Kurang Modular

Konfigurasi:

* Nginx
* PHP
* Database
* MinIO

masih tersebar dan tidak memiliki boundary yang jelas.

---

# Target Arsitektur Baru

## Struktur Utama

```txt
rsch-apps/
│
├── compose/
│   ├── base/
│   ├── apps/
│   └── profiles/
│
├── apps/
│
├── docker/
│
├── env/
│
├── scripts/
│
├── sources/
│
├── storage/
│
├── ansible/
│
├── compose.yml
├── .env
└── rsch
```

---

# Struktur Compose Baru

## Base Infrastructure

```txt
compose/
└── base/
    ├── network.yml
    ├── web.yml
    ├── database.yml
    ├── redis.yml
    ├── minio.yml
    ├── phpmyadmin.yml
    └── mailpit.yml
```

Tujuan:

Semua service umum dikelompokkan menjadi infrastructure layer.

Contoh:

web.yml

* nginx
* reverse proxy

database.yml

* mysql
* mariadb

minio.yml

* object storage

redis.yml

* cache
* queue backend

---

## Application Compose

```txt
compose/
└── apps/
    ├── siimut.yml
    ├── ikp.yml
    ├── iam.yml
    └── lms.yml
```

Berisi:

* php-fpm
* queue worker
* scheduler

khusus untuk aplikasi tersebut.

Tidak boleh berisi:

* nginx
* mysql
* redis
* minio

karena sudah berada pada layer infrastructure.

---

## Profile Compose

```txt
compose/
└── profiles/
    ├── dev.yml
    ├── prod.yml
    └── monitoring.yml
```

Digunakan untuk override environment.

Contoh:

dev.yml

* xdebug
* mailpit
* verbose logging

prod.yml

* optimized workers
* production settings

---

# Struktur Aplikasi Baru

## Setiap App Menjadi Self Contained Module

Contoh:

```txt
apps/
└── siimut/
    ├── app.yml
    ├── Dockerfile
    ├── nginx.conf
    ├── .env.example
    └── scripts/
```

---

## app.yml Menjadi Single Source of Truth

Contoh:

```yaml
name: siimut

repo: git@github.com:org/siimut.git

branch: main

image: registry.example.com/siimut

port: 8000

domain: siimut.local

database: siimut_db

queue: true

scheduler: true

php_version: "8.4"
```

Semua automation membaca file ini.

---

# Docker Directory

```txt
docker/
├── nginx/
├── php/
├── mysql/
├── minio/
├── redis/
└── supervisor/
```

Tujuan:

Semua konfigurasi container berada dalam satu tempat.

---

# Environment Directory

```txt
env/
├── common.env
├── dev.env
└── prod.env
```

Tidak perlu lagi puluhan file env yang sulit dipelihara.

Konfigurasi spesifik aplikasi dipindahkan ke:

apps/<app>/.env.example

---

# Source Directory

```txt
sources/
├── siimut/
├── ikp/
├── iam/
└── lms/
```

Digunakan sebagai hasil clone repository.

Direkomendasikan masuk gitignore.

---

# Storage Directory

```txt
storage/
├── mysql/
├── redis/
├── minio/
└── logs/
```

Semua data persisten terkumpul pada satu lokasi.

---

# Script Directory

```txt
scripts/
├── prepare/
├── build/
├── deploy/
├── health/
├── maintenance/
└── generate/
```

Tujuan:

Menghilangkan puluhan file shell script di root repository.

---

# CLI Platform

Buat satu entrypoint utama:

```bash
./rsch
```

Command yang harus tersedia:

## Application

```bash
./rsch prepare siimut
./rsch prepare ikp
./rsch prepare iam
./rsch prepare lms
```

Function:

* clone repository
* create env
* generate compose
* register nginx
* create database

---

## Build

```bash
./rsch build siimut
```

Function:

* build image
* tag image
* push registry

---

## Runtime

```bash
./rsch up siimut
./rsch down siimut
./rsch restart siimut
```

---

## Logs

```bash
./rsch logs siimut
```

---

## Health

```bash
./rsch health siimut
```

---

## Infrastructure

```bash
./rsch infra up
./rsch infra down
./rsch infra restart
```

Menjalankan:

* nginx
* mysql
* redis
* minio

tanpa aplikasi.

---

# Automation yang Harus Dibuat

Ketika menjalankan:

```bash
./rsch prepare lms
```

Sistem harus otomatis:

1. Membaca apps/lms/app.yml
2. Clone repository
3. Generate env
4. Membuat database
5. Membuat compose app
6. Register nginx
7. Menyiapkan volume
8. Menjalankan migration (opsional)
9. Menjalankan aplikasi

Tanpa perlu edit file manual.

---

# Hasil Akhir yang Diharapkan

Developer cukup melakukan:

```bash
./rsch prepare lms
```

atau

```bash
./rsch prepare siimut
```

dan seluruh kebutuhan aplikasi otomatis terdaftar ke platform.

Menambahkan aplikasi baru cukup dengan membuat:

```txt
apps/
└── nama-app/
    ├── app.yml
    ├── Dockerfile
    ├── nginx.conf
    └── .env.example
```

tanpa mengubah banyak file pusat.

Arsitektur baru harus memprioritaskan:

* Modularity
* Readability
* Maintainability
* Scalability
* Automation
* Minimal Configuration Changes
* Single Command Operations
