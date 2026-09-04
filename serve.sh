#!/usr/bin/env bash
# artirdim — Laravel'i Emergent preview portu (3000) üzerinde servis eder.
# MariaDB + Redis'i (yoksa) başlatır, DB'yi hazırlar, ardından php artisan serve'i foreground çalıştırır.
set -e
cd "$(dirname "$0")"

# --- MariaDB ---
mkdir -p /var/lib/mysql /var/run/mysqld
chown -R mysql:mysql /var/lib/mysql /var/run/mysqld 2>/dev/null || true
[ -d /var/lib/mysql/mysql ] || mariadb-install-db --user=mysql --datadir=/var/lib/mysql >/dev/null 2>&1
pgrep -x mariadbd >/dev/null || (nohup mariadbd --user=mysql --datadir=/var/lib/mysql >/tmp/mariadb.log 2>&1 &)

# --- Redis ---
pgrep -x redis-server >/dev/null || (nohup redis-server >/tmp/redis.log 2>&1 &)

# DB hazır olana kadar bekle
for i in $(seq 1 30); do mysqladmin ping >/dev/null 2>&1 && break; sleep 1; done

# Veritabanı ve kullanıcı (yoksa) oluştur
mysql -u root <<'SQL' 2>/dev/null || true
CREATE DATABASE IF NOT EXISTS auction CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'auction'@'localhost' IDENTIFIED BY 'auction123';
CREATE USER IF NOT EXISTS 'auction'@'127.0.0.1' IDENTIFIED BY 'auction123';
GRANT ALL PRIVILEGES ON auction.* TO 'auction'@'localhost';
GRANT ALL PRIVILEGES ON auction.* TO 'auction'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL

# Şema yoksa (pod sıfırlanmışsa) migrate + seed
if ! mysql -u auction -pauction123 auction -e "SHOW TABLES LIKE 'users';" 2>/dev/null | grep -q users; then
  php artisan migrate --force || true
  php artisan db:seed --force || true
  php artisan storage:link || true
fi

php artisan config:clear >/dev/null 2>&1 || true

exec php artisan serve --host=0.0.0.0 --port=3000
