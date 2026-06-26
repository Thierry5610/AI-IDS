-- Seed a small demo database and table for the benign db generator.
CREATE DATABASE IF NOT EXISTS labdb;
USE labdb;

CREATE TABLE IF NOT EXISTS events (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  msg        VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO events (msg) VALUES
  ('seed one'), ('seed two'), ('seed three'), ('seed four'), ('seed five');

GRANT ALL PRIVILEGES ON labdb.* TO 'labuser'@'%';
FLUSH PRIVILEGES;
