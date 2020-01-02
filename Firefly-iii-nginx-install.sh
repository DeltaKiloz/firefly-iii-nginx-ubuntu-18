#!/bin/bash

echo 'What is the name of your website (please include .com)'
read website

echo 'Give me a valid email address for Lets Encrypt certificate:'
read certbotemail

dbpass=$(openssl rand -base64 16)
mysqlroot=$(openssl rand -base64 16)

# change webroot if you want to change where your serving your website from
webroot=/var/www


apt-get update
apt install software-properties-common
add-apt-repository ppa:ondrej/php -y
add-apt-repository ppa:certbot/certbot -y
apt-get update
apt-get upgrade -y
apt-get install -y nginx 'php7.3' php7.3-cli php7.3-common php7.3-json php7.3-opcache php7.3-mysql php7.3-mbstring libmcrypt-dev php7.3-zip php7.3-fpm php7.3-bcmath php7.3-intl php7.3-xml php7.3-curl php7.3-gd 'libapache2-mod-php7.3' php7.3-ldap

debconf-set-selections <<< "mysql-server-5.7 mysql-server/root_password password $mysqlroot"
sudo debconf-set-selections <<< "mysql-server-5.7 mysql-server/root_password_again password $mysqlroot"
apt-get -y install 'mysql-server-5.7'
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer


sudo chown -R www-data:www-data $webroot
sudo chmod -R 775 $webroot/firefly-iii/storage
sudo -u www-data composer create-project grumpydictator/firefly-iii --no-dev  -d $webroot --prefer-dist firefly-iii 4.8.2


cat >/tmp/user.sql <<EOL
CREATE USER 'firefly'@'localhost' IDENTIFIED BY '${dbpass}';
CREATE DATABASE firefly;
GRANT ALL PRIVILEGES ON firefly.* TO 'firefly'@'localhost';
FLUSH PRIVILEGES;
EOL

mysql -u root --password="$mysqlroot"< /tmp/user.sql >/dev/null 2>&1
sed -i "s:"DB_CONNECTION=pgsql":"DB_CONNECTION=mysql":" $webroot/firefly-iii/.env
sed -i "s:"DB_HOST=firefly_iii_db":"DB_HOST=localhost":" $webroot/firefly-iii/.env
sed -i "s:"DB_PORT=5432":"DB_PORT=3306":" $webroot/firefly-iii/.env
sed -i "s:"DB_USERNAME=homestead":"DB_USERNAME=firefly":" $webroot/firefly-iii/.env
sed -i "s:"DB_DATABASE=homestead":"DB_DATABASE=firefly":" $webroot/firefly-iii/.env
sed -i "s:"DB_PASSWORD=secret_firefly_password":"DB_PASSWORD=$dbpass":" $webroot/firefly-iii/.env
#sed -i "s:"APP_URL=http://localhost":"APP_URL=http://$website":" $webroot/firefly-iii/.env

sudo chown -R www-data:www-data $webroot/firefly-iii
sudo chmod -R 775 $webroot/firefly-iii/storage

php $webroot/firefly-iii/artisan migrate:refresh --seed
php $webroot/firefly-iii/artisan firefly:upgrade-database
php $webroot/firefly-iii/artisan passport:install

# creates your config file in sites-available
cat >/etc/nginx/sites-available/$website <<EOL
server {
   listen 80;
   root /var/www/firefly-iii/public;
   index index.php index.html index.htm index.nginx-debian.html;
   server_name $website www.$website;

   location / {
       try_files \$uri \$uri/ /index.php?\$query_string;
       autoindex on;
       sendfile off;
   }

   location ~ \.php$ {
      include snippets/fastcgi-php.conf;
      fastcgi_pass unix:/run/php/php7.3-fpm.sock;
   }

   location ~ /\.ht {
      deny all;
   }
}
EOL

# symlink your config file to sites-enabled
ln -s /etc/nginx/sites-available/$website /etc/nginx/sites-enabled/

# make sure that the default config is unlinked from sites-enabled
unlink /etc/nginx/sites-enabled/default

# stop apache2 so that nginx can serve the webpages
service apache2 stop
systemctl start nginx

apt install python-certbot-nginx -y
certbot --nginx -n -d $website -d www.$website --email $certbotemail --agree-tos --redirect --hsts

#a2dissite 000-default.conf
#a2ensite $website.conf
#a2enmod rewrite
#service apache2 restart

cat <<EOF

###### Store these in a safe place they will dissapear after this ######


Mysql root password is  ${mysqlroot}
Firefly db user password is  ${dbpass}

EOF
