#!/bin/bash

# Define ANSI color codes
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

# Source phpbrew configuration
source ~/.phpbrew/bashrc

# Set non-interactive mode for package installations/updates
export DEBIAN_FRONTEND=noninteractive

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run as root${RESET}"
  exit
fi

# Initialize variables with default values
username=""
password=""
php_versions=""
mysql_password=""
ssh_port=22
ssh_key=""

# Function to log progress with color
function log_progress {
  echo -e "${GREEN}Installing $1...${RESET}"
}

# Function to log completion with color
function log_complete {
  echo -e "${GREEN}$1 installed${RESET}"
}

# Function to log warnings with color
function log_warning {
  echo -e "${YELLOW}WARNING: $1${RESET}"
}

# Function to log errors with color
function log_error {
  echo -e "${RED}ERROR: $1${RESET}"
}

# Function to display configurations
function display_configurations {
  echo -e "${YELLOW}Configurations:${RESET}"
  echo "Username: $username"
  echo "Password: $password"
  echo "PHP Versions: $php_versions"
  echo "MySQL Password: $mysql_password"
  echo "SSH Port: $ssh_port"
  echo "SSH Key: $ssh_key"
}

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
    -sp|--ssh-port)
      ssh_port="$2"
      shift 2
      ;;
    -sk|--ssh-key)
      ssh_key="$2"
      shift 2
      ;;
    *)
      echo "Invalid argument: $1"
      exit 1
      ;;
  esac
done

# Function to set SSH key for the new user
function set_ssh_key {
  if [ -n "$ssh_key" ]; then
    mkdir -p "/home/$username/.ssh"
    echo "$ssh_key" > "/home/$username/.ssh/authorized_keys"
    chown -R "$username:$username" "/home/$username/.ssh"
    chmod 700 "/home/$username/.ssh"
    chmod 600 "/home/$username/.ssh/authorized_keys"
  fi
}

# Make a sudo user
log_progress "creating user $username"
useradd -m -s /bin/bash "$username"
echo "$username:$password" | chpasswd
usermod -aG sudo "$username"
log_complete "user $username"

# Install phpbrew
log_progress "installing phpbrew"
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
log_complete "phpbrew"

# Install additional packages
log_progress "installing additional packages"
sudo apt update -y
packages=("libxml2-dev" "libbz2-dev" "libcurl4-openssl-dev" "libdb-dev" "libjpeg-dev" "libpng-dev" "libXpm-dev" "libfreetype6-dev" "libmysqlclient-dev" "libt1-dev" "libgd2-xpm-dev" "libgmp-dev" "libpspell-dev" "librecode-dev" "libldap2-dev" "libssl-dev" "libreadline-dev" "libtidy-dev" "libxslt-dev")

for package in "${packages[@]}"; do
  sudo apt install -y "$package"
done

log_complete "additional packages installed"

# Install and switch to PHP versions
IFS=',' read -ra php_versions_array <<< "$php_versions"
for php_version in "${php_versions_array[@]}"; do
  log_progress "installing PHP $php_version"
  
  # Check if the PHP version is installed, if not, install it
  if ! phpbrew list | grep -q "$php_version"; then
    log_warning "PHP $php_version not found. Installing..."
    phpbrew install "$php_version" +default
  fi
  
  # Activate the PHP version
  phpbrew use "$php_version"
  log_complete "PHP $php_version installed"
done


# Change SSH port
log_progress "changing SSH port to $ssh_port"
sed -i "s/#Port 22/Port $ssh_port/" /etc/ssh/sshd_config
log_complete "SSH port changed to $ssh_port"

# Set SSH key for the new user
log_progress "setting SSH key for $username"
set_ssh_key
log_complete "SSH key set for $username"

# Disable root login
log_progress "disabling root login"
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
log_complete "root login disabled"

# Disable SSH password authentication
log_progress "disabling SSH password authentication"
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
log_complete "SSH password authentication disabled"

# Add SSH and OpenSSH to UFW
log_progress "configuring UFW"
ufw allow "$ssh_port/tcp"
ufw allow OpenSSH
log_complete "UFW configured"

# Enable UFW and restart SSH service
log_progress "enabling UFW and restarting SSH"
ufw --force enable
systemctl restart sshd
log_complete "UFW enabled and SSH restarted"

# Install Nginx
log_progress "installing Nginx"
sudo apt install -y nginx
log_complete "Nginx installed"

# Configure MySQL with specific options
log_progress "configuring MySQL"
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
log_complete "MySQL installed"

# Install Composer
log_progress "installing Composer"
sudo apt update
sudo apt install -y unzip
cd ~
curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
HASH=$(curl -sS https://composer.github.io/installer.sig)
php -r "if (hash_file('SHA384', '/tmp/composer-setup.php') === '$HASH') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('/tmp/composer-setup.php'); } echo PHP_EOL;"
php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer
rm /tmp/composer-setup.php
log_complete "Composer installed"

# Setup Nginx and Let's Encrypt
log_progress "setting up Nginx and Let's Encrypt"
sudo apt update
sudo apt install -y certbot python3-certbot-nginx
sudo ufw allow 'Nginx Full'
sudo ufw delete allow 'Nginx HTTP'

# Setup Certbot cronjob for renewing certificates
(crontab -l ; echo "15 3 * * * /usr/bin/certbot renew --quiet") | crontab -

# Restart services
log_progress "restarting services"
systemctl restart nginx
systemctl restart php"${php_versions_array[0]}"-fpm

# Display configurations at the end
display_configurations

echo "Script completed successfully."