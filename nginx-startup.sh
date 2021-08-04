#!/bin/bash

sudo apt update
sudo apt install nginx -y

LB_INTERNAL_IP=$(curl http://metadata/computeMetadata/v1/instance/attributes/LB_INTERNAL_IP -H "Metadata-Flavor: Google")

cat << EOF > /etc/nginx/sites-enabled/default

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
        }
        location /demo/ {
                proxy_http_version 1.1;
                proxy_pass http://$LB_INTERNAL_IP:8080/demo/;
        }
        location /img/picture.jpg {
            proxy_pass https://storage.googleapis.com/gcp-homework-web-bucket/Wallpaper-16-10.png;
        }

}

EOF

sudo systemctl restart nginx
