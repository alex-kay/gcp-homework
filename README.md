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

#create buckets

gsutil mb gs://gcp-homework-app-bucket123
gsutil mb gs://gcp-homework-web-bucket123
gsutil mb gs://gcp-homework-log-bucket123

# move startup scripts, sample app and picture there
gsutil cp *-startup.sh gs://gcp-homework-app-bucket123
wget https://tomcat.apache.org/tomcat-7.0-doc/appdev/sample/sample.war
gsutil cp sample.war gs://gcp-homework-app-bucket123
wget https://github.com/gregsramblings/google-cloud-4-words/raw/master/Wallpaper-16-10.png
gsutil cp Wallpaper-16-10.png gs://gcp-homework-web-bucket123

#make web bucket public
gsutil iam ch allUsers:roles/storage.legacyObjectReader gs://gcp-homework-web-bucket123

# create vpc and 2 subnets, and proxy-only subnet
gcloud compute networks create homework-vpc \
    --subnet-mode=custom \
    --mtu=1460 \
    --bgp-routing-mode=regional

gcloud compute networks subnets create homework-app-subnet \
    --range=10.0.1.0/24 \
    --network=homework-vpc \
    --region=us-central1

gcloud compute networks subnets create homework-web-subnet \
    --range=10.0.2.0/24 \
    --network=homework-vpc \
    --region=us-central1

gcloud compute networks subnets create homework-proxy-subnet \
    --purpose=INTERNAL_HTTPS_LOAD_BALANCER \
    --role=ACTIVE \
    --region=us-central1 \
    --network=homework-vpc \
    --range=10.0.0.0/24

# add firewall rule to allow 8080 from vpc instances
gcloud compute firewall-rules create homework-allow-tomcat-ingress \
    --direction=INGRESS \
    --priority=1000 \
    --network=homework-vpc \
    --action=ALLOW \
    --rules=tcp:8080 \
    --source-ranges=10.0.0.0/16 \
    --target-tags=homework-backend-tag

# add firewall rule for 80 for frontend 
gcloud compute firewall-rules create homework-frontend-ingress \
    --direction=INGRESS \
    --priority=1000 \
    --network=homework-vpc \
    --action=ALLOW \
    --rules=tcp:80 \
    --source-ranges=0.0.0.0/0 \
    --target-tags=homework-frontend-tag

# add firewall rule for all instances SSH reachability
gcloud compute firewall-rules create homework-allow-ssh \
    --direction=INGRESS \
    --priority=1000 \
    --network=homework-vpc \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges=0.0.0.0/0

# add firewall rule for health checks
gcloud compute firewall-rules create homework-allow-health-check \
    --network=homework-vpc \
    --action=allow \
    --direction=ingress \
    --source-ranges=130.211.0.0/22,35.191.0.0/16,209.85.152.0/22,209.85.204.0/22 \
    --target-tags=allow-health-check \
    --rules=tcp:80,tcp:8080

```

## 2. create MIG for backend with installed tomcat and on boot download demo application from bucket

```bash

# create instance template for Tomcat
gcloud compute instance-templates create homework-backend-template \
    --machine-type=g1-small \
    --subnet=projects/homework-1-321812/regions/us-central1/subnetworks/homework-app-subnet \
    --metadata=startup-script-url=https://storage.googleapis.com/gcp-homework-app-bucket123/tomcat-startup.sh,APP_BUCKET=gcp-homework-app-bucket123 \
    --region=us-central1 \
    --tags=homework-backend-tag,allow-health-check \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-balanced \
    --boot-disk-device-name=homework-backend-template

```

## 3. setup autoscaling by CPU (think about scale down)

```bash

# create instance group for Tomcat
gcloud compute instance-groups managed create homework-backend-group-1 \
    --base-instance-name=homework-backend-group-1 \
    --template=homework-backend-template \
    --size=1 \
    --zone=us-central1-a

# create autoscaling policy by CPU
gcloud beta compute instance-groups managed set-autoscaling "homework-backend-group-1" \
    --zone "us-central1-a" \
    --cool-down-period "60" \
    --max-num-replicas "4" \
    --min-num-replicas "1" \
    --target-cpu-utilization "0.6" \
    --mode "on"

```

## 4. create LB

- here i created LB through console..below are commented lines i was trying to recreate this via CLI

![tomcat lb](screens/Screenshot%202021-08-04%20at%2013.39.00.png)

```bash

# add named 8080 port
gcloud compute instance-groups managed set-named-ports "homework-backend-group-1" \
    --zone "us-central1-a" \
    --named-ports=tomcat-service:8080


# create health check for tomcat
gcloud compute health-checks create tcp homework-tomcat-check --port 8080

# backend service 
gcloud compute backend-services create homework-tomcat-backend-service \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --protocol=HTTP \
    --port-name=tomcat-service \
    --health-checks=homework-tomcat-check \
    --region=us-central1

# add backend service to instance group
gcloud compute backend-services add-backend homework-tomcat-backend-service \
    --instance-group=homework-backend-group-1 \
    --instance-group-zone=us-central1-a \
    --region=us-central1

# url map
gcloud compute url-maps create homework-tomcat-frontend \
  --default-service=homework-tomcat-backend-service \
  --region=us-central1

# proxy
gcloud compute target-http-proxies create homework-backend-lb-proxy \
  --url-map=homework-tomcat-frontend \
  --url-map-region=us-central1 \
  --region=us-central1

# forwarding rule
gcloud compute forwarding-rules create homework-tomcat-frontend-lb \
  --load-balancing-scheme=INTERNAL_MANAGED \
  --network=homework-vpc \
  --subnet=homework-app-subnet \
  --address=10.0.1.10 \
  --ports=8080 \
  --region=us-central1 \
  --target-http-proxy=homework-backend-lb-proxy \
  --target-http-proxy-region=us-central1

```

## 5. add one more MIG for frontend with nginx, by path /demo/ show demo app from bucket, by path /img/picture.jpg show file from bucket

```bash

# create instance template for Nginx
gcloud compute instance-templates create homework-frontend-template \
    --machine-type=g1-small \
    --subnet=projects/homework-1-321812/regions/us-central1/subnetworks/homework-web-subnet \
    --metadata=startup-script-url=https://storage.googleapis.com/gcp-homework-app-bucket123/nginx-startup.sh,LB_INTERNAL_IP=$(gcloud compute forwarding-rules describe homework-tomcat-frontend-lb --region=us-central1 --format="value(IPAddress)") \
    --region=us-central1 \
    --tags=homework-frontend-tag,allow-health-check \
    --boot-disk-size=10GB \
    --boot-disk-type=pd-balanced \
    --boot-disk-device-name=homework-frontend-template


# create instance group for Nginx
gcloud compute instance-groups managed create homework-frontend-group-1 \
    --base-instance-name=homework-frontend-group-1 \
    --template=homework-frontend-template \
    --size=1 \
    --zone=us-central1-a

# create autoscaling policy by CPU
gcloud beta compute instance-groups managed set-autoscaling "homework-frontend-group-1" \ 
    --zone "us-central1-a" \
    --cool-down-period "60" \
    --max-num-replicas "4" \
    --min-num-replicas "1" \
    --target-cpu-utilization "0.6" \
    --mode "on"

```

- here i created LB for Nginx group, through console..below recreated via CLI

![nginx lb](screens/Screenshot%202021-08-04%20at%2013.39.48.png)

```bash

# create nginx health check
gcloud compute health-checks create http homework-nginx-health-check \
    --port 80

# nginx backend service create
gcloud compute backend-services create homework-web-backend-service \
    --protocol=HTTP \
    --port-name=http \
    --health-checks=http-basic-check \
    --global

# add instance group to backend
gcloud compute backend-services add-backend homework-web-backend-service \
    --instance-group=homework-frontend-group-1 \
    --instance-group-zone=us-central1-a \
    --global

# get external LB ip address
gcloud compute addresses create homework-nginx-lb-ip \
    --ip-version=IPV4 \
    --global

# url map
gcloud compute url-maps create homework-nginx-frontend \
    --default-service homework-web-backend-service

# proxy
gcloud compute target-http-proxies create homework-frontend-lb-proxy \
    --url-map=homework-nginx-frontend

# forwarding rule
gcloud compute forwarding-rules create http-content-rule \
    --address=homework-nginx-lb-ip \
    --global \
    --target-http-proxy=homework-frontend-lb-proxy \
    --ports=80

```

- external load balancer IP in browser:

![/demo/](screens/Screenshot%202021-08-04%20at%2013.42.24.png)

![/img/picture.jpg](screens/Screenshot%202021-08-04%20at%2013.42.35.png)

## 6. setup export of nginx logs to bucket/BigQuery

```bash

# create sink
gcloud logging sinks create homework-log-sink storage.googleapis.com/gcp-homework-log-bucket123 \
    --log-filter='resource.type="gce_instance" AND log_name="projects/homework-1-321812/logs/nginx-access" AND log_name="projects/homework-1-321812/logs/nginx-access"'

# add sink serviceaccount as admin of log bucket
gsutil iam ch $(gcloud logging sinks describe homework-log-sink2 --format="value(writerIdentity)"):roles/storage.objectAdmin gs://gcp-homework-log-bucket123

```

- logs in bucket:

![log-bucket](screens/Screenshot%202021-08-04%20at%2013.55.09.png)

- also to BigQuery (created sink via console):

![bigQuery](screens/Screenshot%202021-08-04%20at%2006.04.45.png)
