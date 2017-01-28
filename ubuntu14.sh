#!/bin/bash

# go to root
cd

# Install Pritunl
#!/bin/bash
echo "deb http://repo.mongodb.org/apt/ubuntu trusty/mongodb-org/3.2 multiverse" > /etc/apt/sources.list.d/mongodb-org-3.2.list
echo "deb http://repo.pritunl.com/stable/apt trusty main" > /etc/apt/sources.list.d/pritunl.list
apt-key adv --keyserver hkp://keyserver.ubuntu.com --recv 42F3E95A2C4F08279C4960ADD68FA50FEA312927
apt-key adv --keyserver hkp://keyserver.ubuntu.com --recv 7568D9BB55FF9E5287D586017AE645C0CF8E292A
apt-get --assume-yes update
apt-get --assume-yes install pritunl mongodb-org
service pritunl start

# Install Squid
apt-get -y install squid3
cp /etc/squid3/squid.conf /etc/squid3/squid.conf.orig
wget -O /etc/squid3/squid.conf "https://raw.githubusercontent.com/zero9911/pritunl/master/conf/squid.conf" 
MYIP=`ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0' | grep -v '192.168'`;
sed -i s/xxxxxxxxx/$MYIP/g /etc/squid3/squid.conf;
service squid3 restart

# Enable Firewall
sudo ufw allow 22,80,81,222,443,8080,9700,60000/tcp
sudo ufw allow 22,80,81,222,443,8080,9700,60000/udp
sudo yes | ufw enable

sudo apt-get update
sudo apt-get install apache2
sudo apt-get install mysql-server libapache2-mod-auth-mysql php5-mysql
sudo mysql_install_db
sudo /usr/bin/mysql_secure_installation
sudo apt-get install php5 libapache2-mod-php5 php5-mcrypt

## Install Modules
sudo a2enmod rewrite
## Suppress qualified domain name warning
sudo sh -c 'echo "
# Suppress qualified domain name warning
ServerName localhost" >> /etc/apache2/apache2.conf'
## Allow .htaccess files
find="<Directory \/var\/www\/>\n\tOptions Indexes FollowSymLinks\n\tAllowOverride None\n\tRequire all granted\n<\/Directory>"
replace="<Directory \/var\/www\/>\n\tOptions Indexes FollowSymLinks\n\tAllowOverride All\n\tRequire all granted\n<\/Directory>"
sudo perl -0777 -i.original -pe "s/$find/$replace/igs" /etc/apache2/apache2.conf

# create prod
mkdir /var/www/html/docroot
find /var/www/html -type f -exec chmod 644 {} +
find /var/www/html -type d -exec chmod 775 {} +
chown -R root:www-data /var/www/html

# create stage
mkdir /var/www/stage
mkdir /var/www/stage/docroot
find /var/www/stage -type f -exec chmod 644 {} +
find /var/www/stage -type d -exec chmod 775 {} +
chown root:www-data /var/www/stage

# create symlink

ln -s /var/www/stage/docroot /var/www/html/docroot/stage

## Change docroot
find="DocumentRoot \/var\/www\/html"
replace="DocumentRoot \/var\/www\/html\/docroot"
sudo perl -0777 -i.original -pe "s/$find/$replace/igs" /etc/apache2/sites-available/000-default.conf

## Add user to www-data group
sudo usermod -a -G www-data $USER

sudo service apache2 restart

# Create new database
function create_new_db {
  echo -n "Enter password for the MySQL root account: "
  read -s rootpass
  echo ""
  Q00="CREATE DATABASE $dbname;"
  Q01="USE $dbname;"
  Q02="CREATE USER $dbuser@localhost IDENTIFIED BY '$dbpass';"
  Q03="GRANT ALL PRIVILEGES ON $dbname.* TO $dbuser@localhost;"
  Q04="FLUSH PRIVILEGES;"
  SQL0="${Q00}${Q01}${Q02}${Q03}${Q04}"
  mysql -v -u "root" -p$rootpass -e"$SQL0"
}

# Download WordPress, modify wp-config.php, set permissions
function install_wp {
  wget http://wordpress.org/latest.tar.gz
  tar xzvf latest.tar.gz
  cp -rf wordpress/** ./
  rm -R wordpress
  cp wp-config-sample.php wp-config.php
  sed -i "s/database_name_here/$dbname/g" wp-config.php
  sed -i "s/username_here/$dbuser/g" wp-config.php
  sed -i "s/password_here/$dbpass/g" wp-config.php
  wget -O wp.keys https://api.wordpress.org/secret-key/1.1/salt/
  sed -i '/#@-/r wp.keys' wp-config.php
  sed -i "/#@+/,/#@-/d" wp-config.php
  mkdir wp-content/uploads
  find . -type d -exec chmod 755 {} \;
  find . -type f -exec chmod 644 {} \;
  chown -R :www-data wp-content/uploads
  chown -R $USER:www-data *
  chmod 640 wp-config.php
  rm -f latest.tar.gz
  rm -f wp-install.sh
  rm -f wp.keys
}

# Create .htaccess file
function generate_htaccess {
  touch .htaccess
  chown :www-data .htaccess
  chmod 644 .htaccess
  bash -c "cat > .htaccess" << _EOF_
# Block the include-only files.
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^wp-admin/includes/ - [F,L]
RewriteRule !^wp-includes/ - [S=3]
RewriteRule ^wp-includes/[^/]+\.php$ - [F,L]
RewriteRule ^wp-includes/js/tinymce/langs/.+\.php - [F,L]
RewriteRule ^wp-includes/theme-compat/ - [F,L]
</IfModule>

# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress

# Prevent viewing of .htaccess file
<Files .htaccess>
order allow,deny
deny from all
</Files>
# Prevent viewing of wp-config.php file
<files wp-config.php>
order allow,deny
deny from all
</files>
# Prevent directory listings
Options All -Indexes
_EOF_
}

# Create robots.txt file
function generate_robots {
  touch robots.txt
  bash -c "cat > robots.txt" << _EOF_
# Sitemap: absolute url
User-agent: *
Disallow: /cgi-bin/
Disallow: /wp-admin/
Disallow: /wp-includes/
Disallow: /wp-content/plugins/
Disallow: /wp-content/cache/
Disallow: /wp-content/themes/
Disallow: /trackback/
Disallow: /comments/
Disallow: */trackback/
Disallow: */comments/
Disallow: wp-login.php
Disallow: wp-signup.php
_EOF_
}

# Download WordPress plugins
function download_plugins {
  cd wp-content/plugins/
  # W3 Total Cache
  plugin_url=$(curl -s https://wordpress.org/plugins/w3-total-cache/ | egrep -o "https://downloads.wordpress.org/plugin/[^']+")
  wget $plugin_url
  # Theme Test Drive
  plugin_url=$(curl -s https://wordpress.org/plugins/theme-test-drive/ | egrep -o "https://downloads.wordpress.org/plugin/[^']+")
  wget $plugin_url
  # Login LockDown
  plugin_url=$(curl -s https://wordpress.org/plugins/login-lockdown/ | egrep -o "https://downloads.wordpress.org/plugin/[^']+")
  wget $plugin_url
  # Easy Theme and Plugin Upgrades
  plugin_url=$(curl -s https://wordpress.org/plugins/easy-theme-and-plugin-upgrades/ | egrep -o "https://downloads.wordpress.org/plugin/[^']+")
  wget $plugin_url
  # Install unzip package
  apt-get install unzip
  # Unzip all zip files
  unzip \*.zip
  # Remove all zip files
  rm -f *.zip
  echo ""
  cd ../..
}


##### User inputs

echo -n "WordPress database name: "
read dbname
echo -n "WordPress database user: "
read dbuser
echo -n "WordPress database password: "
read -s dbpass
echo ""
echo -n "Install Wordpress? [Y/n] "
read instwp
echo -n "Create a NEW database with entered info? [Y/n] "
read newdb


##### Main

if [ "$newdb" = y ] || [ "$newdb" = Y ]
then
  create_new_db
  install_wp
  generate_htaccess
  generate_robots
  download_plugins
else
  if [ "$instwp" = y ] || [ "$instwp" = Y ]
  then
    install_wp
    generate_htaccess
    generate_robots
    download_plugins
  fi
fi

# Install Vnstat
apt-get -y install vnstat
vnstat -u -i eth0
sudo chown -R vnstat:vnstat /var/lib/vnstat
service vnstat restart

# Install Vnstat GUI
cd /home/vps/public_html/
wget http://www.sqweek.com/sqweek/files/vnstat_php_frontend-1.5.1.tar.gz
tar xf vnstat_php_frontend-1.5.1.tar.gz
rm vnstat_php_frontend-1.5.1.tar.gz
mv vnstat_php_frontend-1.5.1 vnstat
cd vnstat
sed -i "s/\$iface_list = array('eth0', 'sixxs');/\$iface_list = array('eth0');/g" config.php
sed -i "s/\$language = 'nl';/\$language = 'en';/g" config.php
sed -i 's/Internal/Internet/g' config.php
sed -i '/SixXS IPv6/d' config.php
cd

# About
clear
echo "-Pritunl"
echo "-MongoDB"
echo "-Vnstat"
echo "-Web Server"
echo "-Squid Proxy Port 7166,60000"
echo "Vnstat     :  http://$MYIP:81/vnstat"
echo "Pritunl    :  https://$MYIP"
pritunl setup-key
