#!/bin/bash

sudo apt update
sudo apt install nginx -y

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
                proxy_pass $LB_INTERNAL_IP:8080;
                try_files $uri $uri/ =404;
        }

        location /demo/ {
            proxy_pass $LB_INTERNAL_IP:8080/sample/;
        }

        location /img/picture.jpg {
            proxy_pass https://storage.googleapis.com/gcp-homework-web-bucket/Wallpaper-16-10.png;
        }

}

EOF

sudo systemctl restart nginx
