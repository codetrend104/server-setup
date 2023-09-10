#!/bin/bash

# Set non-interactive mode for package installations/updates
export DEBIAN_FRONTEND=noninteractive

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

# Configure MySQL with specific options
cat <<EOF | sudo debconf-set-selections
mysql-server-8.0 mysql-server/root_password password $mysql_password
mysql-server-8.0 mysql-server/root_password_again password $mysql_password
mysql-server-8.0 mysql-server-8.0/group-bysv GROUP BY into temporary tables
mysql-server-8.0 mysql-server-8.0/prefix-core question
mysql-server-8.0 mysql-server-8.0/really_downgrade question
mysql-server-8.0 mysql-server-8.0/reverse_host_lookup boolean false
mysql-server-8.0 mysql-server-8.0/validate_password_check_user_name boolean true
mysql-server-8.0 mysql-server-8.0/validate_password_length integer 8
mysql-server-8.0 mysql-server-8.0/validate_password_mixed_case_count integer 1
mysql-server-8.0 mysql-server-8.0/validate_password_number_count integer 1
mysql-server-8.0 mysql-server-8.0/validate_password_policy select 2
mysql-server-8.0 mysql-server-8.0/validate_password_special_char_count integer 1
EOF

# Install MySQL server with the specific options
sudo apt install -y mysql-server-8.0

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
systemctl restart php"${php_versions_array[0]}"-fpm

echo "Script completed successfully."
