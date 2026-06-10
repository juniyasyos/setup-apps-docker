# RSCH Application Platform & Deployment Orchestrator

> Platform Docker multi-aplikasi untuk deployment dan manajemen aplikasi Laravel secara modular, scalable, dan otomatis.

**Status** · Platform Restructure v2.0

---

## Aplikasi Terkelola

| Aplikasi | Port | Domain | Deskripsi |
|---|---|---|---|
| [SIIMUT](apps/siimut/) | 8000 | siimut.local | Sistem Informasi Imunisasi |
| [IKP](apps/ikp/) | 8200 | ikp.local | Incident Reporting & Pelaporan |
| [IAM Server](apps/iam/) | 8100 | iam.local | Authentication & SSO Server |
| [LMS](apps/lms/) | 7000 | lms.local | Learning Management System CitraHusada |

## Arsitektur

```
rsch-apps/
├── compose/          # Docker Compose manifests (modular)
│   ├── base/         #   Infrastructure + web services
│   ├── apps/         #   Application per-app services
│   ├── profiles/     #   Environment overrides
│   └── build.yml     #   Build manifests
├── apps/             # Application definitions
│   ├── siimut/
│   ├── ikp/
│   ├── iam/
│   └── lms/
├── docker/           # Container configurations
│   ├── nginx/
│   ├── php/
│   └── db/
├── env/              # Environment files
├── scripts/          # Automation scripts
├── sources/          # Cloned repositories (gitignored)
├── storage/          # Persistent data (gitignored)
├── compose.yml       # Main compose manifest (include web.yml)
└── rsch              # CLI entrypoint
```

Detail struktur lengkap: [docs/STRUCTURE.md](docs/STRUCTURE.md)

## Quick Start

```bash
# 1. Persiapan infrastruktur
./rsch infra up

# 2. Siapkan aplikasi (clone + setup)
./rsch prepare siimut

# 3. Jalankan semua service
./rsch up

# 4. Cek status
./rsch health siimut
```

Dokumentasi lengkap: [docs/USAGE.md](docs/USAGE.md)

## CLI Reference

```bash
./rsch prepare <app>      # Clone, setup env, install deps
./rsch build <app>        # Build Docker image
./rsch up [--dev|--prod]  # Start all services
./rsch down               # Stop all services
./rsch restart <app>      # Restart app services
./rsch logs <app>         # Tail app logs
./rsch health <app>       # Health check
./rsch infra up|down      # Infrastructure only
./rsch list               # List available apps
```

## Prasyarat

- **Docker Engine** 24.x+ dengan Docker Compose v2
- **Git** untuk cloning repository
- **Port tersedia**: 8000, 8100, 8200, 7000, 9090, 9091, 8888

### Setup Docker

```bash
./rsch scripts/prepare/install-docker.sh
```

## License

Proyek internal — RSCH (Rumah Sakit Citra Husada)
