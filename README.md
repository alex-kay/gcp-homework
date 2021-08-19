# gcp-homework

## steps

1. ✔️Create bucket for application files and another one for static web files (think about permissions)
2. ✔️create MIG for backend with installed tomcat and on boot download demo application from bucket
3. ✔️setup autoscaling by CPU (think about scale down)
4. ✔️create LB
5. ✔️add one more MIG for frontend with nginx, by path /demo/ show demo app from bucket, by path /img/picture.jpg show file from bucket
6. ✔️setup export of nginx logs to bucket/BigQuery
7. ❌Заменить агента для экспорта логов ( если был гугловский - переключится на стронее решение и наоборот )
8. ✔️Заменить базовую операционную систему б группе бекенда ( ubuntu <-> centos )
9. ✔️Настроить внутренний LB таким образом, чтоб он передавал трафик только в случае если на целевом хосте tomcat возвращает http status 20x
10. ✔️Разобраться как можно при scale down запретить убивать конкретную ноду, на которой сейчас крутиться длинний процес
11. ✔️Почитать про pub/sub и события

* ❌Создать функцию (python3) которая будет запускаться через pubsub и выводить сообщение
* ❌Настроить атоматический запуск этой функции каждый час
* ❌(опционально) - функция должна подключаться к BigQuery и выводить статистику по http ответам за последний час
* ❌Создать еще одну фунцию которая будет запускаться каждый раз когда nginx выдает ошибку 404 и выводить текст ошибки

## 1. Create bucket for application files and another one for static web files (think about permissions)

```bash

# get project id to reference later
GCLOUD_PROJECT=$(gcloud config get-value project)

# create a timestamp to name buckets and reference later
BUCKETS_NAME=gcp-homework-bucket-$(date +%s)

#create buckets

gsutil mb gs://app-$BUCKETS_NAME
gsutil mb gs://web-$BUCKETS_NAME
gsutil mb gs://log-$BUCKETS_NAME

# move startup scripts, sample app and picture there
gsutil cp *-startup.sh gs://app-$BUCKETS_NAME
wget https://tomcat.apache.org/tomcat-7.0-doc/appdev/sample/sample.war
gsutil cp sample.war gs://app-$BUCKETS_NAME
wget https://github.com/gregsramblings/google-cloud-4-words/raw/master/Wallpaper-16-10.png
gsutil cp Wallpaper-16-10.png gs://web-$BUCKETS_NAME

#make web bucket public
gsutil iam ch allUsers:roles/storage.legacyObjectReader gs://web-$BUCKETS_NAME

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

# create instance template for Tomcat (Default Debian 10 image)
gcloud compute instance-templates create homework-backend-template-debian \
    --machine-type=g1-small \
    --subnet=projects/$GCLOUD_PROJECT/regions/us-central1/subnetworks/homework-app-subnet \
    --metadata=startup-script-url=https://storage.googleapis.com/app-$BUCKETS_NAME/tomcat-startup.sh,APP_BUCKET=app-$BUCKETS_NAME \
    --region=us-central1 \
    --tags=homework-backend-tag,allow-health-check \
    --boot-disk-size=20GB \
    --boot-disk-type=pd-balanced \
    --boot-disk-device-name=homework-backend-template \
    --image=debian-10-buster-v20210721 \
    --image-project=debian-cloud

# or same, but with Centos 7 image
gcloud compute instance-templates create homework-backend-template-centos \
    --machine-type=g1-small \
    --subnet=projects/$GCLOUD_PROJECT/regions/us-central1/subnetworks/homework-app-subnet \
    --metadata=startup-script-url=https://storage.googleapis.com/app-$BUCKETS_NAME/tomcat-startup.sh,APP_BUCKET=app-$BUCKETS_NAME \
    --region=us-central1 \
    --tags=homework-backend-tag,allow-health-check \
    --boot-disk-size=20GB \
    --boot-disk-type=pd-balanced \
    --boot-disk-device-name=homework-backend-template \
    --image=centos-7-v20210721 \
    --image-project=centos-cloud

```

## 3. setup autoscaling by CPU (think about scale down)

```bash

# create instance group for Tomcat (chose Debian template)
gcloud compute instance-groups managed create homework-backend-group-1 \
    --base-instance-name=homework-backend-group-1 \
    --template=homework-backend-template-debian \
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

![tomcat lb](screens/Screenshot%202021-08-04%20at%2013.39.00.png)

```bash

# add named 8080 port
gcloud compute instance-groups managed set-named-ports "homework-backend-group-1" \
    --zone "us-central1-a" \
    --named-ports=tomcat-service:8080


# create health check for tomcat
gcloud compute health-checks create http homework-tomcat-check \
    --port 8080 \
    --region=us-central1

# backend service 
gcloud compute backend-services create homework-tomcat-backend-service \
    --load-balancing-scheme=INTERNAL_MANAGED \
    --protocol=HTTP \
    --port-name=tomcat-service \
    --health-checks=homework-tomcat-check \
    --health-checks-region=us-central1 \
    --region=us-central1 \
    --connection-draining-timeout=360

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
    --subnet=projects/$GCLOUD_PROJECT/regions/us-central1/subnetworks/homework-web-subnet \
    --metadata=startup-script-url=https://storage.googleapis.com/app-$BUCKETS_NAME/nginx-startup.sh,WEB_BUCKET=web-$BUCKETS_NAME,LB_INTERNAL_IP=$(gcloud compute forwarding-rules describe homework-tomcat-frontend-lb --region=us-central1 --format="value(IPAddress)") \
    --region=us-central1 \
    --tags=homework-frontend-tag,allow-health-check \
    --boot-disk-size=20GB \
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

![nginx lb](screens/Screenshot%202021-08-04%20at%2013.39.48.png)

```bash

# create nginx health check
gcloud compute health-checks create http homework-nginx-health-check \
    --port 80

# nginx backend service create
gcloud compute backend-services create homework-web-backend-service \
    --protocol=HTTP \
    --port-name=http \
    --health-checks=homework-nginx-health-check \
    --global \
    --connection-draining-timeout=360

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

# get external load balancer address
EXT_LB_IP=$(gcloud compute addresses describe homework-nginx-lb-ip --global --format="value(address)")
echo Visit http://$EXT_LB_IP/ for Tomcat default page
echo Visit http://$EXT_LB_IP/demo/ for demo application
echo Visit http://$EXT_LB_IP/img/picture.jpg for image

```

* external load balancer IP in browser:

![/demo/](screens/Screenshot%202021-08-04%20at%2013.42.24.png)

![/img/picture.jpg](screens/Screenshot%202021-08-04%20at%2013.42.35.png)

## 6. setup export of nginx logs to bucket/BigQuery

```bash

# create sink to Storage bucket
gcloud logging sinks create homework-log-bucket-sink storage.googleapis.com/log-$BUCKETS_NAME \
    --log-filter='resource.type="gce_instance" AND log_name="projects/$GCLOUD_PROJECT/logs/nginx-access" AND log_name="projects/$GCLOUD_PROJECT/logs/nginx-access"'

# add sink serviceaccount as admin of log bucket
gsutil iam ch $(gcloud logging sinks describe homework-log-bucket-sink --format="value(writerIdentity)"):roles/storage.objectAdmin gs://log-$BUCKETS_NAME

# create bigQuery dataset for logs
# bq --location=us-central1 mk $GCLOUD_PROJECT:homeworklogdataset

# create sink to bigQuery
# gcloud logging sinks create homework-log-bq-sink \
#     bigquery.googleapis.com/projects/$GCLOUD_PROJECT/datasets/homeworklogdataset \
#     --log-filter='resource.type="gce_instance" AND log_name="projects/$GCLOUD_PROJECT/logs/nginx-access" AND log_name="projects/$GCLOUD_PROJECT/logs/nginx-access"'

# add bigquery role to sink serviceaccount
# TODO
#

```

* logs in bucket:

![log-bucket](screens/Screenshot%202021-08-04%20at%2013.55.09.png)

* also to BigQuery (created sink via console):

![bigQuery](screens/Screenshot%202021-08-04%20at%2006.04.45.png)

## 8. Заменить базовую операционную систему б группе бекенда

```bash

# update Tomcat group to use Centos template
gcloud beta compute instance-groups managed rolling-action start-update homework-backend-group-1 \
    --project=$GCLOUD_PROJECT \
    --type='proactive' \
    --max-surge=1 \
    --max-unavailable=1 \
    --min-ready=0 \
    --minimal-action='replace' \
    --most-disruptive-allowed-action='replace' \
    --replacement-method='substitute' \
    --version=template=projects/$GCLOUD_PROJECT/global/instanceTemplates/homework-backend-template-centos \
    --zone=us-central1-a

```

## Создать функцию (python3) которая будет запускаться через pubsub и выводить сообщение

![cloudFunction](screens/Screenshot%202021-08-19%20231823.png)

## Настроить атоматический запуск этой функции каждый час

* Done this using Cloud Scheduler, which triggers PubSub topic that trigger the function

```bash

# create a topic
gcloud pubsub topics create homework-topic

# create a subscribtion
gcloud pubsub subscriptions create homework-sub \
    --topic homework-topic

# create a scheduled job
gcloud scheduler jobs create pubsub homework-job \
    --schedule="0 * * * *" \
    --topic=homework-topic \
    --message-body="Hello, it's been an hour!"

# create function
cd function

gcloud functions deploy homework-function \
    --region=us-central1 \
    --runtime=python39 \
    --trigger-topic=homework-topic

cd ..



```

![cloudScheduler](screens/Screenshot%202021-08-19%20231450.png)
