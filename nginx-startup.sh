#!/bin/bash

sudo apt update
sudo apt install apt-transport-https wget nginx -y

# BEGIN install Stackdriver agents
#

# curl -sSO https://dl.google.com/cloudagents/add-monitoring-agent-repo.sh
# sudo bash add-monitoring-agent-repo.sh --also-install

# curl -sSO https://dl.google.com/cloudagents/add-logging-agent-repo.sh
# sudo bash add-logging-agent-repo.sh --also-install

# (cd /etc/nginx/conf.d/ && sudo curl -O https://raw.githubusercontent.com/Stackdriver/stackdriver-agent-service-configs/master/etc/nginx/conf.d/status.conf)

# sudo service nginx reload

# (cd /etc/stackdriver/collectd.d/ && sudo curl -O https://raw.githubusercontent.com/Stackdriver/stackdriver-agent-service-configs/master/etc/collectd.d/nginx.conf)

# sudo service stackdriver-agent restart

#
# END install Stackdriver agents

# BEGIN installing Filebeat and ELK
#

sudo apt install default-jre -y
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-7.x.list
sudo apt update
sudo apt install filebeat -y

sudo systemctl enable filebeat

sudo filebeat modules enable nginx

sudo filebeat setup -e

sudo systemctl start filebeat


# # example logging file
# wget https://download.elastic.co/demos/logstash/gettingstarted/logstash-tutorial.log.gz
# gzip -d logstash-tutorial.log.gz
# cp logstash-tutorial.log /tmp/
# cat << EOF > /etc/filebeat/filebeat.yml

# filebeat.inputs:
# - type: log
#   paths:
#     - /tmp/logstash-tutorial.log 
# output.logstash:
#   hosts: ["localhost:5044"]

# EOF

# sudo filebeat -e -c /etc/filebeat/filebeat.yml -d "publish" 

# cat << EOF > /tmp/logstash.conf

# input {
#         beats {
#                 port => "5044"
#         }
# }
# output {
#         stdout { codec => rubydebug }
# }

# EOF

# sudo /usr/share/logstash/bin/logstash -f /tmp/logstash.conf --config.test_and_exit



#
# END installing Filebeat and Logstash

LB_INTERNAL_IP=$(curl http://metadata/computeMetadata/v1/instance/attributes/LB_INTERNAL_IP -H "Metadata-Flavor: Google")
WEB_BUCKET=$(curl http://metadata/computeMetadata/v1/instance/attributes/WEB_BUCKET -H "Metadata-Flavor: Google")

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
                # try_files $uri $uri/ =404;
                proxy_http_version 1.1;
                proxy_pass http://$LB_INTERNAL_IP:8080;
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
