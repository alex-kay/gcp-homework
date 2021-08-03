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
APP_BUCKET=gcp-homework-app-bucket123
WEB_BUCKET=gcp-homework-web-bucket123

gsutil mb gs://$APP_BUCKET
gsutil mb gs://$WEB_BUCKET

# move startup scripts, sample app and picture there
gsutil cp *-startup.sh gs://$APP_BUCKET
wget https://tomcat.apache.org/tomcat-7.0-doc/appdev/sample/sample.war
gsutil cp sample.war gs://$APP_BUCKET
wget https://github.com/gregsramblings/google-cloud-4-words/raw/master/Wallpaper-16-10.png
gsutil cp Wallpaper-16-10.png gs://$WEB_BUCKET

#make web bucket public
gsutil iam ch allUsers:roles/storage.legacyObjectReader gs://$WEB_BUCKET

# create vpc and 2 subnets
gcloud compute networks create homework-vpc --subnet-mode=custom --mtu=1460 --bgp-routing-mode=regional

gcloud compute networks subnets create homework-app-subnet --range=10.0.1.0/24 --network=homework-vpc --region=us-central1

gcloud compute networks subnets create homework-web-subnet --range=10.0.2.0/24 --network=homework-vpc --region=us-central1

# add firewall rule to allow 8080 from frontend instances
gcloud compute firewall-rules create homework-allow-tomcat-ingress --direction=INGRESS --priority=1000 --network=homework-vpc --action=ALLOW --rules=tcp:8080 --source-tags=homework-frontend-tag --target-tags=homework-backend-tag

# add firewall rule for 80 for frontend 
gcloud compute firewall-rules create homework-frontend-ingress --direction=INGRESS --priority=1000 --network=homework-vpc --action=ALLOW --rules=tcp:80,tcp:443 --source-ranges=0.0.0.0/0 --target-tags=homework-frontend-tag

gcloud compute firewall-rules create homework-allow-ssh --direction=INGRESS --priority=1000 --network=homework-vpc --action=ALLOW --rules=tcp:22 --source-ranges=0.0.0.0/0

```

## 2. create MIG for backend with installed tomcat and on boot download demo application from bucket

```bash

# create instance template for Tomcat
gcloud compute instance-templates create homework-backend-template --machine-type=g1-small  --metadata=startup-script-url=https://storage.googleapis.com/$APP_BUCKET/tomcat-startup.sh,APP_BUCKET=$APP_BUCKET --tags=homework-backend-tag --boot-disk-size=10GB --boot-disk-type=pd-balanced --boot-disk-device-name=homework-backend-template

# gcloud beta compute instance-templates create homework-backend-template --machine-type=g1-small --subnet=projects/linuxacademypractice1/regions/us-central1/subnetworks/app-subnet --metadata=startup-script-url=https://storage.googleapis.com/gcp-hwww-app-bucket/tomcat-startup.s --region=us-central1 --tags=homework-backend-tag  --boot-disk-size=10GB --boot-disk-type=pd-balanced --boot-disk-device-name=homework-backend-template

```

## 3. setup autoscaling by CPU (think about scale down)

```bash

# create instance group for Tomcat
gcloud compute instance-groups managed create homework-backend-group-1 --base-instance-name=homework-backend-group-1 --template=homework-backend-template --size=1 --zone=us-central1-a

# create autoscaling policy by CPU
gcloud beta compute instance-groups managed set-autoscaling "homework-backend-group-1" --zone "us-central1-a" --cool-down-period "60" --max-num-replicas "4" --min-num-replicas "1" --target-cpu-utilization "0.6" --mode "on"

```

## 4. create LB

```bash

# add named 8080 port
gcloud compute instance-groups managed set-named-ports "homework-backend-group-1" --zone "us-central1-a" --named-ports=tomcat-service:8080

```

## 5. add one more MIG for frontend with nginx, by path /demo/ show demo app from bucket, by path /img/picture.jpg show file from bucket

```bash

# store internal LB Ip address in variable
LB_INTERNAL_IP=$(gcloud compute forwarding-rules describe lb-internal-frontend --region=us-central1 --format="value(IPAddress)")

# create instance template for Nginx
gcloud compute instance-templates create homework-frontend-template --machine-type=g1-small  --metadata=startup-script-url=https://storage.googleapis.com/$APP_BUCKET/nginx-startup.sh,LB_INTERNAL_IP=$LB_INTERNAL_IP --tags=homework-frontend-tag --boot-disk-size=10GB --boot-disk-type=pd-balanced --boot-disk-device-name=homework-frontend-template

# gcloud beta compute --project=linuxacademypractice1 instance-templates create homework-frontend-template --machine-type=g1-small --subnet=projects/linuxacademypractice1/regions/us-central1/subnetworks/web-subnet --network-tier=PREMIUM --metadata=startup-script-url=https://storage.googleapis.com/gcp-homework-app-bucket/nginx-startup.sh --maintenance-policy=MIGRATE --service-account=450684076389-compute@developer.gserviceaccount.com --scopes=https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/trace.append --region=us-central1 --tags=homework-frontend-tag,http-server --image=debian-10-buster-v20210721 --image-project=debian-cloud --boot-disk-size=10GB --boot-disk-type=pd-balanced --boot-disk-device-name=homework-frontend-template --no-shielded-secure-boot --no-shielded-vtpm --no-shielded-integrity-monitoring --reservation-affinity=any

# create instance group for Nginx
gcloud compute instance-groups managed create homework-frontend-group-1 --base-instance-name=homework-frontend-group-1 --template=homework-frontend-template --size=1 --zone=us-central1-a

# create autoscaling policy by CPU
gcloud beta compute instance-groups managed set-autoscaling "homework-frontend-group-1" --zone "us-central1-a" --cool-down-period "60" --max-num-replicas "4" --min-num-replicas "1" --target-cpu-utilization "0.6" --mode "on"

```
