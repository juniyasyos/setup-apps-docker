# Detail Aplikasi Spesifik (Application Matrix)

Dokumen ini membedah setiap aplikasi yang dikelola oleh orchestrator RSCH secara individual, termasuk spesifikasi teknis, lingkungan, dan ketergantungan layanannya.

---

## 1. SIIMUT (Sistem Informasi Imunisasi Terpadu)
* **Deskripsi**: Sistem Informasi Imunisasi untuk mengelola data imunisasi pasien, logistik vaksin, dan pelaporan di RSCH.
* **Repository**: `https://github.com/juniyasyos/si-imut.git` (Branch: `main`)
* **Framework**: Laravel (PHP 8.4)
* **Port Mapping**:
  * Internal: `9000`
  * Dev: `8010`
  * Prod: `8000`
* **Network & Domain**: `siimut.local`
* **Ketergantungan**:
  * **Database**: `siimut_db` (User: `siimut_user`)
  * **Queue Worker**: Ya (Daemon untuk memproses job di latar belakang)
  * **Scheduler**: Ya (Cron cronjob untuk task terjadwal)
  * **SSO**: Membutuhkan `IAM_JWT_SECRET` tersinkronisasi dari IAM Server.
  * **Storage**: Terkoneksi dengan bucket MinIO S3 untuk penyimpanan lampiran rekam medis.

## 2. IAM Server (Authentication & SSO Server)
* **Deskripsi**: Identity and Access Management. Bertindak sebagai server SSO terpusat (OAuth2/Passport) untuk seluruh layanan di lingkungan RSCH.
* **Repository**: `https://github.com/juniyasyos/auth-server.git` (Branch: `main`)
* **Framework**: Laravel (PHP 8.4)
* **Port Mapping**:
  * Internal: `9000`
  * Dev: `8110`
  * Prod: `8100`
* **Network & Domain**: `iam.local`
* **Ketergantungan**:
  * **Database**: `iam_db` (User: `iam_user`)
  * **Queue Worker**: Ya
  * **Scheduler**: Ya
  * **Keys**: Saat `prepare` mode berjalan, sistem akan secara otomatis membuat pasangan kunci *OAuth2 Passport RSA Keys* dan menginjeksikannya ke dalam berkas `env/.env.prod.iam`.

## 3. IKP (Incident Reporting & Pelaporan)
* **Deskripsi**: Sistem untuk pelaporan insiden internal rumah sakit guna meningkatkan keselamatan dan layanan pasien.
* **Repository**: `https://github.com/juniyasyos/ikp.git` (Branch: `main`)
* **Framework**: Laravel (PHP 8.4)
* **Port Mapping**:
  * Internal: `9000`
  * Dev: `8210`
  * Prod: `8200`
* **Network & Domain**: `ikp.local`
* **Ketergantungan**:
  * **Database**: `ikp_db` (User: `ikp_user`)
  * **Queue Worker**: Ya
  * **Scheduler**: Ya

## 4. LMS (Learning Management System)
* **Deskripsi**: Learning Management System berbasis Laravel yang dikustomisasi untuk kebutuhan internal edukasi karyawan dan nakes di institusi kesehatan.
* **Repository**: `https://github.com/juniyasyos/lms.git` (Branch: `main`)
* **Framework**: Laravel (PHP 8.4)
* **Port Mapping**:
  * Internal: `9000`
  * Dev: `7110` (Berdasarkan pola) / Default config `7100`
  * Prod: `7100`
* **Network & Domain**: `lms.local`
* **Ketergantungan**:
  * **Database**: `lms_db` (User: `lms_user`)
  * **Queue Worker**: Ya
  * **Scheduler**: Ya

## 5. SMSP (Smartpresence Backend)
* **Deskripsi**: Layanan backend API terpusat untuk absensi dan kehadiran cerdas berbasis geolokasi/wajah.
* **Repository**: `https://github.com/Iannn-vbeta/be-laravel-smartpresence` (Branch: `main`)
* **Framework**: Laravel (PHP 8.4)
* **Port Mapping**:
  * Internal: `9000`
  * Prod: `7200`
* **Network & Domain**: `smsp.local`
* **Ketergantungan**:
  * **Database**: `smsp_db` (User: `smsp_user`)
  * **Queue Worker**: Ya
  * **Scheduler**: Ya

## 6. FE-SMSP (Smartpresence Frontend Static)
* **Deskripsi**: Web antarmuka (frontend) statis untuk layanan Smartpresence.
* **Repository**: `https://github.com/Iannn-vbeta/fe-react-smartpresence.git` (Branch: `main`)
* **Framework**: React / Vite
* **Port Mapping**:
  * Internal / Host: `7250`
* **Network & Routing**: Dikendalikan mandiri melalui proxy nginx internal atau `VITE_API_URL`.

## 7. RBV (Ruang Baca Virtual Platform)
* **Deskripsi**: Ruang Baca Virtual, platform perpustakaan / literatur medis digital untuk tenaga kesehatan.
* **Repository**: `https://github.com/kiflinnadil/new-RBV.git` (Branch: `main`)
* **Framework**: Laravel (PHP 8.4)
* **Port Mapping**:
  * Internal: `9000`
  * Prod: `7300`
* **Ketergantungan**:
  * **Database**: `rbv_db` (User: `rbv_user`)
  * **Queue Worker**: Ya
  * **Scheduler**: Ya

---
> **Catatan Operasional**: Semua aplikasi berbasis Laravel akan menggunakan base template `php-base.yml` yang sudah dikustomisasi untuk mengaktifkan OPcache JIT dan security hardening di production.
