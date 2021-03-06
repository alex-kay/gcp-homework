#!/bin/bash

sudo apt update
sudo apt install apt-transport-https wget -y
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-7.x.list
sudo apt update
sudo apt install default-jre -y
sudo apt install elasticsearch -y

sudo cat << EOF >> /etc/elasticsearch/elasticsearch.yml
network.host: 0.0.0.0
http.port: 9200
cluster.initial_master_nodes: ["$(hostname -I | awk '{gsub(/[ \t]+$/,""); print $0}')"]
EOF

sudo service elasticsearch start
sudo systemctl enable elasticsearch

sudo apt install kibana -y

sudo cat << EOF >> /etc/kibana/kibana.yml
server.host: "0.0.0.0"
server.port: 5601
elasticsearch.hosts: ["http://localhost:9200"]
EOF

sudo service kibana start
sudo systemctl enable kibana

sudo apt install logstash -y

sudo service logstash start
sudo systemctl enable logstash
