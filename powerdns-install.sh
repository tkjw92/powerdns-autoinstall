apt install sudo -y

apt install curl vim git libpq-dev gpg -y
apt install mariadb-server -y

mysql -e "create database powerdns;"
mysql -e "grant all privileges on powerdns.* to 'powerdns'@'%' identified by 'admin';"
mysql -e "flush privileges;"

apt install pdns-server pdns-backend-mysql -y

mysql powerdns < /usr/share/pdns-backend-mysql/schema/schema.mysql.sql

echo "# MySQL Configuration
# Launch gmysql backend
launch+=gmysql
# gmysql parameters
gmysql-host=127.0.0.1
gmysql-port=3306
gmysql-dbname=powerdns
gmysql-user=powerdns
gmysql-password=admin
gmysql-dnssec=yes
# gmysql-socket=" > /etc/powerdns/pdns.d/pdns.local.gmysql.conf

chown pdns: /etc/powerdns/pdns.d/pdns.local.gmysql.conf
chmod 640 /etc/powerdns/pdns.d/pdns.local.gmysql.conf

systemctl restart pdns
systemctl enable pdns

apt install python3-dev virtualenv -y
apt install libsasl2-dev libldap2-dev libssl-dev libxml2-dev libxslt1-dev libxmlsec1-dev libffi-dev pkg-config apt-transport-https virtualenv python3-venv build-essential libmariadb-dev git python3-flask -y
apt install nodejs npm -y

curl -sL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor | sudo tee /usr/share/keyrings/yarnkey.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/yarnkey.gpg] https://dl.yarnpkg.com/debian stable main" | sudo tee /etc/apt/sources.list.d/yarn.list

apt update -y
apt install yarn -y

git clone https://github.com/PowerDNS-Admin/PowerDNS-Admin.git /var/www/html/pdns
virtualenv -p python3 /var/www/html/pdns/flask

source /var/www/html/pdns/flask/bin/activate
pip install --upgrade pip
pip install gunicorn flask

sed -i -e 's/--use-feature=no-binary-enable-wheel-cache lxml==4.9.0/#/g' /var/www/html/pdns/requirements.txt

pip install -r /var/www/html/pdns/requirements.txt

deactivate

sed -i -e 's/pda/powerdns/g' -e 's/changeme/admin/g' /var/www/html/pdns/powerdnsadmin/default_config.py

cd /var/www/html/pdns/
source /var/www/html/pdns/flask/bin/activate
export FLASK_APP=powerdnsadmin/__init__.py
flask db upgrade

yarn install --pure-lockfile
flask assets build

deactivate

sed -i -e 's/# api=no/api=yes/g' -e 's/# api-key=/api-key=secretapi/g' /etc/powerdns/pdns.conf
systemctl restart pdns

apt install nginx -y

echo "server {
  listen	*:80;
  server_name               _;

  index                     index.html index.htm index.php;
  root                      /var/www/html/pdns;
  access_log                /var/log/nginx/pdnsadmin_access.log combined;
  error_log                 /var/log/nginx/pdnsadmin_error.log;

  client_max_body_size              10m;
  client_body_buffer_size           128k;
  proxy_redirect                    off;
  proxy_connect_timeout             90;
  proxy_send_timeout                90;
  proxy_read_timeout                90;
  proxy_buffers                     32 4k;
  proxy_buffer_size                 8k;
  proxy_set_header                  Host \$host;
  proxy_set_header                  X-Real-IP \$remote_addr;
  proxy_set_header                  X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_headers_hash_bucket_size    64;

  location ~ ^/static/  {
    include  /etc/nginx/mime.types;
    root /var/www/html/pdns/powerdnsadmin;

    location ~*  \.(jpg|jpeg|png|gif)$ {
      expires 365d;
    }

    location ~* ^.+.(css|js)$ {
      expires 7d;
    }
  }

  location / {
    proxy_pass            http://unix:/run/pdnsadmin/socket;
    proxy_read_timeout    120;
    proxy_connect_timeout 120;
    proxy_redirect        off;
  }

}" > /etc/nginx/conf.d/powerdns-admin.conf

rm -rf /etc/nginx/sites-enabled/default

chown -R www-data: /var/www/html/pdns
systemctl restart nginx

echo "[Unit]
Description=PowerDNS-Admin
Requires=pdnsadmin.socket
After=network.target

[Service]
PIDFile=/run/pdnsadmin/pid
User=pdns
Group=pdns
WorkingDirectory=/var/www/html/pdns
ExecStart=/var/www/html/pdns/flask/bin/gunicorn --pid /run/pdnsadmin/pid --bind unix:/run/pdnsadmin/socket 'powerdnsadmin:create_app()'
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStop=/bin/kill -s TERM \$MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/pdnsadmin.service

echo "[Unit]
Description=PowerDNS-Admin socket

[Socket]
ListenStream=/run/pdnsadmin/socket

[Install]
WantedBy=sockets.target" > /etc/systemd/system/pdnsadmin.socket

mkdir -p /run/pdnsadmin/
echo "d /run/pdnsadmin 0755 pdns pdns -" >> /etc/tmpfiles.d/pdnsadmin.conf

chown -R pdns: /run/pdnsadmin/
chown -R pdns: /var/www/html/pdns/powerdnsadmin/

systemctl daemon-reload
systemctl enable --now pdnsadmin.service pdnsadmin.socket


systemctl status pdnsadmin.service pdnsadmin.socket
