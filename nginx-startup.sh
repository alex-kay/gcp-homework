#!/bin/bash

# detecting OS distro and installing nginx

. /etc/os-release
if [[ "$ID" == "centos" ]]; then
        sudo yum install nginx -y
        SITE_PATH="/etc/nginx/conf.d/default.conf"
elif [[ "$ID" == "debian" ]]; then
        sudo apt update
        sudo apt install nginx -y
        SITE_PATH="/etc/nginx/sites-enabled/default"
fi


# BEGIN install Stackdriver agents
#
curl -sSO https://dl.google.com/cloudagents/add-monitoring-agent-repo.sh
sudo bash add-monitoring-agent-repo.sh --also-install

curl -sSO https://dl.google.com/cloudagents/add-logging-agent-repo.sh
sudo bash add-logging-agent-repo.sh --also-install

(cd /etc/nginx/conf.d/ && sudo curl -O https://raw.githubusercontent.com/Stackdriver/stackdriver-agent-service-configs/master/etc/nginx/conf.d/status.conf)

sudo service nginx reload

(cd /etc/stackdriver/collectd.d/ && sudo curl -O https://raw.githubusercontent.com/Stackdriver/stackdriver-agent-service-configs/master/etc/collectd.d/nginx.conf)

sudo service stackdriver-agent restart
#
# END install Stackdriver agents

LB_INTERNAL_IP=$(curl http://metadata/computeMetadata/v1/instance/attributes/LB_INTERNAL_IP -H "Metadata-Flavor: Google")
WEB_BUCKET=$(curl http://metadata/computeMetadata/v1/instance/attributes/WEB_BUCKET -H "Metadata-Flavor: Google")

cat << EOF > $SITE_PATH

server {
        listen 80 default_server;
        listen [::]:80 default_server;

        root /var/www/html;

        # Add index.php to the list if you are using PHP
        index index.html index.htm index.nginx-debian.html;

        server_name _;

        location / {
                # First attempt to serve request as file, then
                # as directory, then fall back to displaying a 404.
                try_files $uri $uri/ =404;
                proxy_pass http://$LB_INTERNAL_IP:8080;
                proxy_http_version 1.1;
        }
        location /demo/ {
                proxy_http_version 1.1;
                proxy_pass http://$LB_INTERNAL_IP:8080/demo/;
        }
        location /img/picture.jpg {
                proxy_pass https://storage.googleapis.com/$WEB_BUCKET/Wallpaper-16-10.png;
        }

}

EOF

sudo systemctl restart nginx
