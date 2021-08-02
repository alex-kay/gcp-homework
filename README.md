# gcp-homework

## steps

1. Create bucket for application files and another one for static web files (think about permissions)
2. create MIG for backend with installed tomcat and on boot download demo application from bucket
3. setup autoscaling by CPU (think about scale down)
4. create LB
5. add one more MIG for frontend with nginx, by path /demo/ show demo app from bucket, by path /img/picture.jpg show file from bucket
6. setup export of nginx logs to bucket/BigQuery
7. SSL termination (bonus)

## 1. Create bucket for application files and another one for static web files (think about permissions)

```bash

gsutil mb gs://gcp-hw-app-bucket
gsutil mb gs://gcp-hw-web-bucket
curl -O https://tomcat.apache.org/tomcat-7.0-doc/appdev/sample/sample.war
gsutil cp sample.war gs://gcp-hw-app-bucket
curl -0 https://github.com/gregsramblings/google-cloud-4-words/raw/master/Wallpaper-16-10.png
gsutil cp Wallpaper-16-10.png gs://gcp-hw-web-bucket


gcloud compute networks create homework-vpc --project=linuxacademypractice1 --subnet-mode=custom --mtu=1460 --bgp-routing-mode=regional

gcloud compute networks subnets create app-subnet --project=linuxacademypractice1 --range=10.0.1.0/24 --network=homework-vpc --region=us-central1

gcloud compute networks subnets create web-subnet --project=linuxacademypractice1 --range=10.0.2.0/24 --network=homework-vpc --region=us-central1

```

## 2. create MIG for backend with installed tomcat and on boot download demo application from bucket

```bash

# create instance template for Tomcat
gcloud compute instance-templates create backend-template --machine-type=g1-small  --metadata=startup-script-url=https://storage.googleapis.com/gcp-hwww-app-bucket/tomcat-startup.sh --tags=http-server --boot-disk-size=10GB --boot-disk-type=pd-balanced --boot-disk-device-name=backend-template

```

## 3. setup autoscaling by CPU (think about scale down)

```bash

# create instance group for Tomcat
gcloud compute instance-groups managed create backend-group-1 --base-instance-name=backend-group-1 --template=backend-template --size=1 --zone=us-central1-a

# create autoscaling policy by CPU
gcloud beta compute instance-groups managed set-autoscaling "backend-group-1" --zone "us-central1-a" --cool-down-period "60" --max-num-replicas "4" --min-num-replicas "1" --target-cpu-utilization "0.6" --mode "on"

```

## 4. create LB

```bash

# add named 8080 port
gcloud compute instance-groups managed set-named-ports "backend-group-1" --zone "us-central1-a" --named-ports=tomcat-service:8080

```

## 5. add one more MIG for frontend with nginx, by path /demo/ show demo app from bucket, by path /img/picture.jpg show file from bucket

```bash

# create instance template for Nginx
gcloud compute instance-templates create frontend-template --machine-type=g1-small  --metadata=startup-script-url=https://storage.googleapis.com/gcp-hwww-app-bucket/nginx-startup.sh --tags=http-server --boot-disk-size=10GB --boot-disk-type=pd-balanced --boot-disk-device-name=frontend-template

# create instance group for Nginx
gcloud compute instance-groups managed create frontend-group-1 --base-instance-name=frontend-group-1 --template=frontend-template --size=1 --zone=us-central1-a

# create autoscaling policy by CPU
gcloud beta compute instance-groups managed set-autoscaling "frontend-group-1" --zone "us-central1-a" --cool-down-period "60" --max-num-replicas "4" --min-num-replicas "1" --target-cpu-utilization "0.6" --mode "on"

```
