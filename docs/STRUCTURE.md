# Project Structure — RSCH Application Platform

> Update terakhir: 2026-06-10
> Referensi: [Restructure.md](../Restructure.md), [USAGE.md](USAGE.md)

---

## Root Level

```
rsch-apps/
├── compose/                         # Docker Compose manifests
├── apps/                            # Application definitions
├── docker/                          # Container configurations
├── env/                             # Environment files
├── scripts/                         # Automation
├── sources/                         # Cloned repositories (gitignored)
├── storage/                         # Persistent data (gitignored)
├── ansible/                         # Ansible deployment
│
├── compose.yml                      # Main compose manifest
├── rsch                             # CLI entrypoint (chmod +x)
│
├── repos.csv                        # Repository registry
├── .env.example                     # Template .env
│
├── README.md                        # Project overview
├── Restructure.md                   # Restructure plan (reference)
└── docs/                            # Documentation
    ├── USAGE.md                     # Usage guide
    └── STRUCTURE.md                 # This file
```

---

## `compose/` — Docker Compose Manifests

```
compose/
├── base/                            # Infrastructure services (modular, per-service)
│   ├── infra.yml                    # Aggregator — include semua service
│   ├── network.yml                  # Network rsch-apps_default (172.20.0.0/16)
│   ├── web.yml                      # Nginx reverse proxy (multi-app)
│   ├── database.yml                 # MySQL 8.0 (database-service)
│   ├── minio.yml                    # MinIO S3 + minio-init (bucket creator)
│   ├── phpmyadmin.yml               # phpMyAdmin (profile: dev)
│   └── php-base.yml                 # Shared template: php-app-base, php-worker-base, php-scheduler-base
│
├── apps/                            # Application services (extends php-base.yml)
│   ├── siimut.yml                   # SIIMUT app + queue + scheduler
│   ├── ikp.yml                      # IKP app + queue + scheduler
│   ├── iam.yml                      # IAM app + queue + scheduler
│   └── lms.yml                      # LMS app + queue + scheduler
│
├── profiles/                        # Environment overrides
│   ├── dev.yml                      # Development ports, debug mode
│   └── prod.yml                     # Production ports, APP_DEBUG=false
│
└── build.yml                        # Build manifest (apps/*/Dockerfile)
```

## `apps/` — Application Definitions

```
apps/
├── siimut/                          # Sistem Informasi Imunisasi
│   ├── app.yml                      # Metadata: repo, branch, port, db
│   ├── Dockerfile                   # Build image
│   └── .env.example                 # Template environment
│
├── ikp/                             # Incident Reporting & Pelaporan
│   ├── app.yml
│   ├── Dockerfile
│   └── .env.example
│
├── iam/                             # Authentication & SSO Server
│   ├── app.yml
│   ├── Dockerfile
│   └── .env.example
│
└── lms/                             # Learning Management System
    ├── app.yml
    ├── Dockerfile
    └── .env.example
```

## `docker/` — Container Configurations

```
docker/
├── nginx/
│   ├── nginx.conf                   # Main Nginx config
│   └── nginx-multi-apps.conf        # Virtual hosts: siimut, ikp, iam, lms
│
├── php/
│   ├── Dockerfile.production        # PHP 8.x production image
│   ├── Dockerfile.siimut-standalone # SIIMUT standalone image (legacy)
│   ├── entrypoint.sh                # Dev entrypoint
│   ├── entrypoint-prod.sh           # Production entrypoint
│   ├── entrypoint-iam.sh            # IAM entrypoint
│   ├── entrypoint-siimut-standalone.sh
│   ├── php.ini                      # PHP configuration
│   └── supervisord.conf             # Supervisor (queue + scheduler)
│
└── db/
    ├── my.cnf                       # MySQL configuration
    └── sql/                         # SQL init scripts (auto-execute on first start)
```

## `env/` — Environment Files

```
env/
├── common.env                       # Shared variables (MySQL root creds)
├── dev.env                          # Development config (HOST_IP, ports)
└── prod.env                         # Production config (HOST_IP, ports)
```

> Production secrets (`.env.prod.*`) di-generate oleh `prepare.sh` dan masuk gitignore.

## `scripts/` — Automation

```
scripts/
├── prepare.sh                       # Clone repos, setup env, install deps
├── build.sh                         # Build & push Docker images
├── deploy.sh                        # Start/stop stack (called by rsch CLI)
│
├── prepare/
│   ├── install-docker.sh            # Docker Engine installer
│   └── livewire-publish.sh          # Livewire assets publisher
│
├── build/                           # Build helpers (future)
├── deploy/                          # Deploy helpers (future)
├── generate/                        # Code generators (future)
│
├── health/
│   ├── check-jwt.sh                 # JWT validation check
│   └── check-minio.sh               # MinIO connectivity check
│
└── maintenance/
    ├── diagnose.sh                  # General diagnostics
    ├── diagnose-autoload.sh         # Composer autoload check
    ├── diagnose-iam.sh              # IAM Server check
    ├── diagnose-livewire.sh         # Livewire check
    ├── diagnose-signatory.sh        # Signatory check
    └── fix-network.sh               # Network fix tool
```

## `sources/` — Cloned Repositories (Gitignored)

```
sources/
├── siimut/                          # git clone — branch main
├── ikp/                             # git clone — branch main
├── iam/                             # git clone — branch main
└── lms/                             # git clone — branch main
```

## `storage/` — Persistent Data (Gitignored)

```
storage/
├── mysql/                           # MySQL data
├── redis/                           # Redis data (future)
├── minio/                           # MinIO data
└── logs/                            # Application logs
```

## `ansible/` — Ansible Deployment

```
ansible/
├── inventory.ini                    # Server inventory
├── playbook.yml                     # Main playbook
├── group_vars/
│   └── siimut_servers.yml           # Server group variables
└── templates/
    ├── .env.j2                      # .env template
    └── siimut.service.j2            # Systemd service template
```

---

## Docker Compose Include Graph

```
compose.yml (root)                    compose/base/infra.yml
  ├── extends:                        ├── include: network.yml
  │   compose/apps/*.yml              ├── include: database.yml
  │     └── extends:                  ├── include: minio.yml
  │         php-base.yml              └── include: phpmyadmin.yml
  └── profiles: dev.yml / prod.yml
```

## Network Architecture

| Network | Name | Subnet | Scope |
|---|---|---|---|
| Default | `rsch-apps_default` | 172.20.0.0/16 | Shareable antara infra & apps |

| Service | Container Name | Network Alias |
|---|---|---|
| MySQL | `database-service` | `db` |
| MinIO | `minio` | `minio` |
| phpMyAdmin | `phpmyadmin` | — |
| Nginx | `multi-web` | `web` |
| SIIMUT | `siimut-app` | — |
| IKP | `ikp-app` | — |
| IAM | `iam-app` | `iam-app` |
| LMS | `lms-app` | — |

## Port Map

| Port | Service | Dev | Prod |
|---|---|---|---|
| 8000 | SIIMUT | 8010 | 8000 |
| 8100 | IAM | 8110 | 8100 |
| 8200 | IKP | 8210 | 8200 |
| 7000 | LMS | 7000 | 7000 |
| 9090 | MinIO API | 9090 | 9090 |
| 9091 | MinIO Console | 9091 | 9091 |
| 8888 | phpMyAdmin | 8888 | — |
| 9000 | Portainer (disabled) | 9000 | 9000 |

## Volume Map

| Volume | Mount Target | Driver |
|---|---|---|
| `db_data` | `/var/lib/mysql` | local |
| `db_logs` | `/var/log/mysql` | local |
| `minio_data` | `/data` | local |
| `phpmyadmin_sessions` | `/sessions` | local |
| `nginx_logs` | `/var/log/nginx` | local |
| `{app}_storage` | `/var/www/{app}/storage` | local |
| `{app}_public` | `/var/www/{app}/public` | local |
| `{app}_bootstrap_cache` | `/var/www/{app}/bootstrap/cache` | local |
