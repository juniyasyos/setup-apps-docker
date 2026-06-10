import sys, os

filepath = os.environ['BUILD_YML']
name = os.environ['APP_NAME']
source_dir = os.environ['SOURCE_DIR']
db_user = os.environ['DB_USER']
db_pass = os.environ['DB_PASSWORD']
database = os.environ['DB_NAME']
name_upper = name.upper()
desc = os.environ['APP_DESC']

with open(filepath, 'r') as f:
    content = f.read()

content = content.rstrip()

build_block = f"""

  ####################################################################################################
  # {desc}
  ####################################################################################################
  {name}:
    build:
      context: .
      dockerfile: apps/{name}/Dockerfile
      args:
        UID: "1000"
        GID: "1000"
        TZ: "Asia/Jakarta"
        APP_NAME: "{desc}"
        APP_ENV: "production"
        APP_DIR: "{source_dir}"
        DB_HOST: "database-service"
        DB_USERNAME: "{db_user}"
        DB_PASSWORD: "{db_pass}"
        DB_DATABASE: "{database}"
        AWS_ACCESS_KEY_ID: "admin"
        AWS_SECRET_ACCESS_KEY: "password"
        AWS_BUCKET: "{name}"
        AWS_URL: "http://minio:9090/{name}"
        AWS_ENDPOINT: "http://minio:9090"
        BUILD_TIMESTAMP: "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    image: {name}:${{{name_upper}_VERSION:-latest}}
    pull_policy: never
"""

content += build_block + '\n'

with open(filepath, 'w') as f:
    f.write(content)
print("OK")
