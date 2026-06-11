-- =================================================
-- {{DB_NAME}} Database
-- App: {{APP_NAME}}
-- =================================================
CREATE DATABASE IF NOT EXISTS {{DB_NAME}}
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '{{DB_USER}}'@'%'
  IDENTIFIED BY '{{DB_PASSWORD}}';

GRANT ALL PRIVILEGES
  ON {{DB_NAME}}.* TO '{{DB_USER}}'@'%';

CREATE USER IF NOT EXISTS '{{DB_USER}}_readonly'@'%'
  IDENTIFIED BY '{{APP_NAME}}@ReadOnly2025!';

GRANT SELECT
  ON {{DB_NAME}}.* TO '{{DB_USER}}_readonly'@'%';