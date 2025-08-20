#!/bin/bash

# ?? Laravel + Next.js Full-Stack Setup Script
# For Ubuntu 20.04–24.04+
# Usage: ./setup.sh <php_version> <db_type: mysql|pgsql> [--swoole]

PHP_VERSION=${1:-"8.2"}
DB_TYPE=${2:-"mysql"}
INSTALL_SWOLE=false
MYSQL_ROOT_PASSWORD="Msdsl@2024"

if [[ "$3" == "--swoole" ]]; then
  INSTALL_SWOLE=true
fi

echo "?? Starting Setup with:"
echo "?? PHP Version: $PHP_VERSION"
echo "?? DB Type: $DB_TYPE"
echo "?? Swoole: $INSTALL_SWOLE"
echo ""

echo "?? Updating system..."
apt update && apt upgrade -y

echo "?? Installing core packages..."
apt install -y git curl unzip software-properties-common lsb-release ca-certificates gnupg

echo "?? Installing PHP $PHP_VERSION and extensions..."
add-apt-repository ppa:ondrej/php -y
apt update
apt install -y php$PHP_VERSION php$PHP_VERSION-cli php$PHP_VERSION-mbstring php$PHP_VERSION-xml \
  php$PHP_VERSION-bcmath php$PHP_VERSION-curl php$PHP_VERSION-mysql php$PHP_VERSION-zip \
  php$PHP_VERSION-gd php$PHP_VERSION-tokenizer php$PHP_VERSION-intl php$PHP_VERSION-common \
  php$PHP_VERSION-sqlite3 php$PHP_VERSION-fpm php$PHP_VERSION-readline

update-alternatives --set php /usr/bin/php$PHP_VERSION

echo "?? PHP Version: $(php -v | head -n 1)"

if [ "$INSTALL_SWOLE" = true ]; then
  echo "?? Installing PHP Swoole extension..."
  apt install -y php-pear php$PHP_VERSION-dev
  pecl install swoole
  echo "extension=swoole.so" > /etc/php/$PHP_VERSION/cli/conf.d/30-swoole.ini
fi

echo "?? Installing Composer..."
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

if [[ "$DB_TYPE" == "mysql" ]]; then
  echo "?? Installing MySQL..."
  debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD"
  debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD"
  apt install -y mysql-server
  echo "?? Configuring MySQL..."
  mysql -uroot <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';
FLUSH PRIVILEGES;
EOF
elif [[ "$DB_TYPE" == "pgsql" ]]; then
  echo "?? Installing PostgreSQL..."
  apt install -y postgresql postgresql-contrib
  systemctl enable postgresql
  systemctl start postgresql
fi

echo "?? Installing Redis..."
apt install -y redis-server
systemctl enable redis
systemctl start redis

echo "?? Installing Supervisor..."
apt install -y supervisor
systemctl enable supervisor
systemctl start supervisor

echo "?? Installing Nginx..."
apt install -y nginx
systemctl enable nginx
systemctl start nginx

echo "?? Installing Node.js (LTS) and npm..."
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt install -y nodejs

echo "?? Installing PM2..."
npm install -g pm2

echo "?? Setting permissions for /var/www/html..."
chown -R www-data:www-data /var/www/html
chmod -R 755 /var/www/html

echo "? All tools installed!"
echo "------------------------------------------------------"
echo "? PHP $PHP_VERSION, Composer, $DB_TYPE, Redis, Nginx, Node.js, PM2, Supervisor"
echo "?? MySQL root password: $MYSQL_ROOT_PASSWORD"
echo "?? Project directory: /var/www/html"
echo "?? Clone Laravel or Next.js projects and configure manually"
echo "------------------------------------------------------"