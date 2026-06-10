-- ================================================
--  MULTI DATABASE INITIALIZATION (SIIMUT & IAM)
--  SAFE FOR RE-RUN / MIGRATION / PRODUCTION
-- ================================================

-- =================================================
--  SIIMUT Database
-- =================================================
CREATE DATABASE IF NOT EXISTS siimut_db
  CHARACTER SET utf8mb4


  COLLATE utf8mb4_unicode_ci;

-- Create main service user (R/W FULL)
CREATE USER IF NOT EXISTS 'siimut_user'@'%'
  IDENTIFIED BY 'siimut-password';

GRANT ALL PRIVILEGES
  ON siimut_db.* TO 'siimut_user'@'%';


-- Optional: readonly user (analytics / Grafana / DWH)
CREATE USER IF NOT EXISTS 'siimut_readonly'@'%'
  IDENTIFIED BY 'Siimut@ReadOnly2025!';

GRANT SELECT ON siimut_db.* TO 'siimut_readonly'@'%';


-- =================================================
--  IAM / SSO Database
-- =================================================
CREATE DATABASE IF NOT EXISTS iam_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- Create IAM user (R/W FULL)
CREATE USER IF NOT EXISTS 'iam_user'@'%'
  IDENTIFIED BY 'iam-password';

GRANT ALL PRIVILEGES
  ON iam_db.* TO 'iam_user'@'%';


-- Optional: readonly user
CREATE USER IF NOT EXISTS 'iam_readonly'@'%'
  IDENTIFIED BY 'Iam@ReadOnly2025!';

GRANT SELECT ON iam_db.* TO 'iam_readonly'@'%';


-- =================================================
--  IKP Database
-- =================================================
CREATE DATABASE IF NOT EXISTS ikp_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- Create IAM user (R/W FULL)
CREATE USER IF NOT EXISTS 'ikp_user'@'%'
  IDENTIFIED BY 'ikp-password';

GRANT ALL PRIVILEGES
  ON ikp_db.* TO 'ikp_user'@'%';


-- Optional: readonly user
CREATE USER IF NOT EXISTS 'ikp_readonly'@'%'
  IDENTIFIED BY 'ikp@ReadOnly2025!';

GRANT SELECT ON ikp_db.* TO 'ikp_readonly'@'%';


-- =================================================
--  LMS Database
-- =================================================
CREATE DATABASE IF NOT EXISTS db_lms_citrahusada
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- Create IAM user (R/W FULL)
CREATE USER IF NOT EXISTS 'lms_user'@'%'
  IDENTIFIED BY 'lms-password';

GRANT ALL PRIVILEGES
  ON db_lms_citrahusada.* TO 'lms_user'@'%';


-- Optional: readonly user
CREATE USER IF NOT EXISTS 'lms_readonly'@'%'
  IDENTIFIED BY 'lms@ReadOnly2025!';

GRANT SELECT ON db_lms_citrahusada.* TO 'lms_readonly'@'%';


-- =================================================
--  Finalize Privileges
-- =================================================
FLUSH PRIVILEGES;

-- =================================================

