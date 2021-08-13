#!/bin/bash

sudo apt update
sudo apt install apt-transport-https wget -y
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo apt-key add -
echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-7.x.list
sudo apt update
sudo apt install elasticsearch -y
# sudo vim /etc/elasticsearch/elasticsearch.yml network.host: "localhost" http.port:9200 cluster.initial_master_nodes: ["10.128.0.2"]
# sudo service elasticsearch start
VM_PRIVATE_IP=$(curl http://metadata/computeMetadata/v1/instance/network-interfaces/0/ip -H "Me
tadata-Flavor: Google")

cat << EOF > /etc/elasticsearch/elasticsearch.yml
network.host: 0.0.0.0
cluster.initial_master_nodes: ["$VM_PRIVATE_IP"]
EOF

sudo service elasticsearch start

sudo systemctl enable elasticsearch

sudo apt install kibana -y

sudo service kibana start

sudo systemctl enable kibana

sudo apt install default-jre -y
sudo apt install logstash -y

sudo service logstash start

sudo systemctl enable logstash