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
CREATE USER IF NOT EXISTS 'siimut_user'@'%' IDENTIFIED BY 'siimut-password';
ALTER USER 'siimut_user'@'%' IDENTIFIED BY 'siimut-password';

GRANT ALL PRIVILEGES
  ON siimut_db.* TO 'siimut_user'@'%';

-- Optional: readonly user (analytics / Grafana / DWH)
CREATE USER IF NOT EXISTS 'siimut_readonly'@'%' IDENTIFIED BY 'Siimut@ReadOnly2025!';
ALTER USER 'siimut_readonly'@'%' IDENTIFIED BY 'Siimut@ReadOnly2025!';

GRANT SELECT ON siimut_db.* TO 'siimut_readonly'@'%';

-- =================================================
--  IAM / SSO Database
-- =================================================
CREATE DATABASE IF NOT EXISTS iam_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- Create IAM user (R/W FULL)
CREATE USER IF NOT EXISTS 'iam_user'@'%' IDENTIFIED BY 'iam-password';
ALTER USER 'iam_user'@'%' IDENTIFIED BY 'iam-password';

GRANT ALL PRIVILEGES
  ON iam_db.* TO 'iam_user'@'%';

-- Optional: readonly user
CREATE USER IF NOT EXISTS 'iam_readonly'@'%' IDENTIFIED BY 'Iam@ReadOnly2025!';
ALTER USER 'iam_readonly'@'%' IDENTIFIED BY 'Iam@ReadOnly2025!';

GRANT SELECT ON iam_db.* TO 'iam_readonly'@'%';

-- =================================================
--  IKP Database
-- =================================================
CREATE DATABASE IF NOT EXISTS ikp_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- Create IAM user (R/W FULL)
CREATE USER IF NOT EXISTS 'ikp_user'@'%' IDENTIFIED BY 'ikp-password';
ALTER USER 'ikp_user'@'%' IDENTIFIED BY 'ikp-password';

GRANT ALL PRIVILEGES
  ON ikp_db.* TO 'ikp_user'@'%';

-- Optional: readonly user
CREATE USER IF NOT EXISTS 'ikp_readonly'@'%' IDENTIFIED BY 'ikp@ReadOnly2025!';
ALTER USER 'ikp_readonly'@'%' IDENTIFIED BY 'ikp@ReadOnly2025!';

GRANT SELECT ON ikp_db.* TO 'ikp_readonly'@'%';

-- =================================================
--  lms Database
-- =================================================
CREATE DATABASE IF NOT EXISTS lms_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'lms_user'@'%' IDENTIFIED BY 'lms_pass123';                                                                          
    ALTER USER 'lms_user'@'%' IDENTIFIED BY 'lms_pass123';
    
GRANT ALL PRIVILEGES
  ON lms_db.* TO 'lms_user'@'%';

CREATE USER IF NOT EXISTS 'lms_user_readonly'@'%' IDENTIFIED BY 'lms@ReadOnly2025!';
ALTER USER 'lms_user_readonly'@'%' IDENTIFIED BY 'lms@ReadOnly2025!';

GRANT SELECT ON lms_db.* TO 'lms_user_readonly'@'%';

-- =================================================
--  rbv Database
-- =================================================
CREATE DATABASE IF NOT EXISTS rbv_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'rbv_user'@'%' IDENTIFIED BY 'rbv_pass123';
ALTER USER 'rbv_user'@'%' IDENTIFIED BY 'rbv_pass123';

GRANT ALL PRIVILEGES
  ON rbv_db.* TO 'rbv_user'@'%';

CREATE USER IF NOT EXISTS 'rbv_user_readonly'@'%' IDENTIFIED BY 'rbv@ReadOnly2025!';
ALTER USER 'rbv_user_readonly'@'%' IDENTIFIED BY 'rbv@ReadOnly2025!';

GRANT SELECT ON rbv_db.* TO 'rbv_user_readonly'@'%';

-- =================================================
-- smsp_db Database
-- App: smsp
-- =================================================
CREATE DATABASE IF NOT EXISTS smsp_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'smsp_user'@'%' IDENTIFIED BY 'smsp_password';
ALTER USER 'smsp_user'@'%' IDENTIFIED BY 'smsp_password';

GRANT ALL PRIVILEGES
  ON smsp_db.* TO 'smsp_user'@'%';

CREATE USER IF NOT EXISTS 'smsp_user_readonly'@'%' IDENTIFIED BY 'smsp@ReadOnly2025!';
ALTER USER 'smsp_user_readonly'@'%' IDENTIFIED BY 'smsp@ReadOnly2025!';

GRANT SELECT
  ON smsp_db.* TO 'smsp_user_readonly'@'%';


-- =================================================
-- template1_db Database
-- App: template-1
-- =================================================
CREATE DATABASE IF NOT EXISTS template1_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'template1_user'@'%'
  IDENTIFIED BY 'template1_password';

GRANT ALL PRIVILEGES
  ON template1_db.* TO 'template1_user'@'%';

CREATE USER IF NOT EXISTS 'template1_user_readonly'@'%'
  IDENTIFIED BY 'template-1@ReadOnly2025!';

GRANT SELECT
  ON template1_db.* TO 'template1_user_readonly'@'%';

FLUSH PRIVILEGES;
