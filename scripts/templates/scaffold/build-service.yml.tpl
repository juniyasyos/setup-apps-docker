  ####################################################################################################
  # {{APP_DESC}}
  ####################################################################################################
  {{APP_NAME}}:
    build:
      context: .
      dockerfile: apps/{{APP_NAME}}/Dockerfile
      args:
        UID: "1000"
        GID: "1000"
        TZ: "Asia/Jakarta"

        APP_NAME: "{{APP_DESC}}"
        APP_ENV: "production"
        APP_DIR: "{{SOURCE_DIR}}"

        DB_HOST: "database-service"
        DB_USERNAME: "{{DB_USER}}"
        DB_PASSWORD: "{{DB_PASSWORD}}"
        DB_DATABASE: "{{DB_NAME}}"

        AWS_ACCESS_KEY_ID: "admin"
        AWS_SECRET_ACCESS_KEY: "password"
        AWS_BUCKET: "{{APP_NAME}}"
        AWS_URL: "http://minio:9090/{{APP_NAME}}"
        AWS_ENDPOINT: "http://minio:9090"

        BUILD_TIMESTAMP: "${BUILD_TIMESTAMP:-manual}"
    image: {{IMAGE_NAME}}:${{{APP_UPPER}}_VERSION:-{{IMAGE_VERSION}}}
    pull_policy: never