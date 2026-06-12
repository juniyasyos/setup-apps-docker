# {{APP_DESC}}
name: service-{{APP_NAME}}

services:
  app:
    extends:
      file: ../base/php-base.yml
      service: php-app-base
    image: {{IMAGE_NAME}}:{{IMAGE_VERSION}}
    container_name: {{APP_NAME}}-app
    working_dir: /var/www/{{SOURCE_DIR}}
    env_file:
      - ../../apps/{{APP_NAME}}/.env.example
    environment:
      APP_ENV: production
      APP_DEBUG: "true"
      APP_WORKDIR: /var/www/{{SOURCE_DIR}}
      PUBLIC_VOLUME: /var/www/{{SOURCE_DIR}}/public
      APP_URL: "http://${HOST_IP:-localhost}:{{APP_PORT}}"
      TRUSTED_PROXIES: "*"

      DB_HOST: database-service
      DB_USERNAME: {{DB_USER}}
      DB_PASSWORD: {{DB_PASSWORD}}
      DB_DATABASE: {{DB_NAME}}

      # Jangan true kalau public volume masih perlu diisi ke shared volume Nginx.
      SKIP_PUBLIC_SYNC: "false"

      AWS_ACCESS_KEY_ID: admin
      AWS_SECRET_ACCESS_KEY: password
      AWS_BUCKET: {{APP_NAME}}
      AWS_URL: http://${HOST_IP:-localhost}:9090/{{APP_NAME}}
      AWS_ENDPOINT: http://minio:9090
    volumes:
      - {{APP_NAME}}_storage:/var/www/{{SOURCE_DIR}}/storage
      - {{APP_NAME}}_bootstrap_cache:/var/www/{{SOURCE_DIR}}/bootstrap/cache
      - {{APP_NAME}}_public:/var/www/{{SOURCE_DIR}}/public
    deploy:
      resources:
        limits:
          memory: 1G
          cpus: "1"
        reservations:
          memory: 512M
          cpus: "0.5"

  queue:
    extends:
      file: ../base/php-base.yml
      service: php-worker-base
    image: {{IMAGE_NAME}}:{{IMAGE_VERSION}}
    container_name: {{APP_NAME}}-queue
    working_dir: /var/www/{{SOURCE_DIR}}
    env_file:
      - ../../apps/{{APP_NAME}}/.env.example
    environment:
      DB_HOST: database-service
      DB_USERNAME: {{DB_USER}}
      DB_PASSWORD: {{DB_PASSWORD}}
      DB_DATABASE: {{DB_NAME}}
    volumes:
      - {{APP_NAME}}_storage:/var/www/{{SOURCE_DIR}}/storage
      - {{APP_NAME}}_bootstrap_cache:/var/www/{{SOURCE_DIR}}/bootstrap/cache
    command: >
      artisan queue:work
        --sleep=5
        --tries=3
        --timeout=120
        --max-jobs=500
        --max-time=3600
    deploy:
      resources:
        limits:
          memory: 384M
          cpus: "0.5"
        reservations:
          memory: 128M
          cpus: "0.25"

  scheduler:
    extends:
      file: ../base/php-base.yml
      service: php-scheduler-base
    image: {{IMAGE_NAME}}:{{IMAGE_VERSION}}
    container_name: {{APP_NAME}}-scheduler
    working_dir: /var/www/{{SOURCE_DIR}}
    env_file:
      - ../../apps/{{APP_NAME}}/.env.example
    environment:
      DB_HOST: database-service
      DB_USERNAME: {{DB_USER}}
      DB_PASSWORD: {{DB_PASSWORD}}
      DB_DATABASE: {{DB_NAME}}
    volumes:
      - {{APP_NAME}}_storage:/var/www/{{SOURCE_DIR}}/storage
      - {{APP_NAME}}_bootstrap_cache:/var/www/{{SOURCE_DIR}}/bootstrap/cache
    command: >
      artisan schedule:work
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: "0.2"
        reservations:
          memory: 64M
          cpus: "0.1"

volumes:
  {{APP_NAME}}_public:
    external: true
    name: {{PUBLIC_VOLUME_NAME}}

  {{APP_NAME}}_storage:
    external: true
    name: {{STORAGE_VOLUME_NAME}}

  {{APP_NAME}}_bootstrap_cache:
    name: {{BOOTSTRAP_CACHE_VOLUME_NAME}}