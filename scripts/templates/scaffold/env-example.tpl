# ===========================================
# {{APP_DESC}}
# Production Environment Example
# ===========================================

APP_NAME="{{APP_NAME}}"
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=${HOST_IP:-http://localhost}:{{APP_PORT}}

APP_WORKDIR=/var/www/{{SOURCE_DIR}}
PUBLIC_VOLUME=/var/www/{{SOURCE_DIR}}/public
TRUSTED_PROXIES=*

# ===========================================
# Database
# ===========================================
DB_CONNECTION=mysql
DB_HOST=database-service
DB_PORT=3306
DB_DATABASE={{DB_NAME}}
DB_USERNAME={{DB_USER}}
DB_PASSWORD={{DB_PASSWORD}}

# ===========================================
# Cache, Queue, Session
# ===========================================
CACHE_DRIVER=file
QUEUE_CONNECTION=database
SESSION_DRIVER=database
SESSION_LIFETIME=120

# ===========================================
# Redis
# ===========================================
REDIS_HOST=redis
REDIS_PASSWORD=null
REDIS_PORT=6379

# ===========================================
# Mail
# ===========================================
MAIL_MAILER=smtp
MAIL_HOST=smtp.example.com
MAIL_PORT=587
MAIL_USERNAME=
MAIL_PASSWORD=
MAIL_ENCRYPTION=tls
MAIL_FROM_ADDRESS=noreply@example.com
MAIL_FROM_NAME="${APP_NAME}"

# ===========================================
# MinIO / S3
# ===========================================
AWS_ACCESS_KEY_ID=admin
AWS_SECRET_ACCESS_KEY=password
AWS_DEFAULT_REGION=us-east-1
AWS_BUCKET={{APP_NAME}}
AWS_ENDPOINT=http://minio:9090
AWS_URL=${HOST_IP:-http://localhost}:9090/{{APP_NAME}}
AWS_USE_PATH_STYLE_ENDPOINT=true

# ===========================================
# Logging
# ===========================================
LOG_CHANNEL=stack
LOG_LEVEL=debug

# ===========================================
# App Runtime
# ===========================================
SKIP_PUBLIC_SYNC=false