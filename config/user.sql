CREATE USER IF NOT EXISTS 'terraform' IDENTIFIED BY 'terraform';

CREATE DATABASE IF NOT EXISTS terraform;

ALTER DATABASE terraform
  DEFAULT CHARACTER SET utf8
  DEFAULT COLLATE utf8_general_ci;

GRANT ALL PRIVILEGES ON terraform.* TO 'terraform' IDENTIFIED BY 'terraform';