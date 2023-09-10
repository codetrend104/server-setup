#!/bin/bash

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit
fi

# Get arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    -u|--username)
      username="$2"
      shift 2
      ;;
    -p|--password)
      password="$2"
      shift 2
      ;;
    -php|--php-versions)
      php_versions="$2"
      shift 2
      ;;
    -mysql|--mysql-password)
      mysql_password="$2"
      shift 2
      ;;
    *)
      echo "Invalid argument: $1"
      exit 1
      ;;
  esac
done

# Make a sudo user
useradd -m -s /bin/bash "$username"
echo "$username:$password" | chpasswd
usermod -aG sudo "$username"

# Install phpbrew
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y software-properties-common
sudo add-apt-repository -y ppa:ondrej/php
sudo apt update
sudo apt install -y curl build-essential automake autoconf bison libxml2-dev libbz2-dev libcurl4-openssl-dev libdb-dev libjpeg-dev libpng-dev libXpm-dev libfreetype6-dev libmysqlclient-dev libt1-dev libgd2-xpm-dev libgmp-dev libpspell-dev librecode-dev libldap2-dev libssl-dev libreadline-dev libtidy-dev libxslt-dev
curl -L -O https://github.com/phpbrew/phpbrew/releases/latest/download/phpbrew.phar
chmod +x phpbrew.phar
sudo mv phpbrew.phar /usr/local/bin/phpbrew
phpbrew init
echo '[[ -e ~/.phpbrew/bashrc ]] && source ~/.phpbrew/bashrc' >> ~/.bashrc
source ~/.bashrc

# Install and switch to PHP versions
IFS=',' read -ra php_versions_array <<< "$php_versions"
for php_version in "${php_versions_array[@]}"; do
  phpbrew install "$php_version" +default
  phpbrew switch "$php_version"
done

# Change SSH port
new_ssh_port=$(( (RANDOM % 49152) + 1024))
sed -i "s/#Port 22/Port $new_ssh_port/" /etc/ssh/sshd_config
echo "New SSH port: $new_ssh_port"

# Disable root login
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

# Disable SSH password authentication
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# Add SSH and OpenSSH to UFW
ufw allow "$new_ssh_port/tcp"
ufw allow OpenSSH

# Enable UFW and restart SSH service
ufw --force enable
systemctl restart sshd

# Install Nginx
sudo apt install -y nginx

# Install MySQL 8
sudo apt update -y
sudo apt install -y mysql-server-8.0

# Set MySQL root password and secure installation
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$mysql_password';"
mysql_secure_installation <<EOF

Y
$mysql_password
$mysql_password
Y
Y
Y
Y
EOF

# Install Composer
sudo apt update
sudo apt install -y unzip
cd ~
curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
HASH=$(curl -sS https://composer.github.io/installer.sig)
php -r "if (hash_file('SHA384', '/tmp/composer-setup.php') === '$HASH') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('/tmp/composer-setup.php'); } echo PHP_EOL;"
php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm /tmp/composer-setup.php

# Setup Nginx and Let's Encrypt
sudo apt update
sudo apt install -y certbot python3-certbot-nginx
sudo ufw allow 'Nginx Full'
sudo ufw delete allow 'Nginx HTTP'

# Setup Certbot cronjob for renewing certificates
(crontab -l ; echo "15 3 * * * /usr/bin/certbot renew --quiet") | crontab -

# Restart services
systemctl restart nginx
systemctl restart php"$php_versions_array[0]"-fpm

echo "Script completed successfully."
