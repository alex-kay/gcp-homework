# gcp-homework

## steps

1. Create bucket for application files and another one for static web files (think about permissions)
2. create MIG for backend with installed tomcat and on boot download demo application from bucket
3. setup autoscaling buy CPU (think about scale down)
​4. create LB
​5. add one more MIG for frontend with nginx, by path /demo/ show demo app from bucket, by path /img/picture.jpg show file from bucket
​6. setup export of nginx logs to bucket/BigQuery
​7. SSL terination (bonus)

## 1. Create bucket for application files and another one for static web files (think about permissions)

```bash
gsutil mb gs://gcp-hw-app-bucket
gsutil mb gs://gcp-hw-web-bucket
curl -O https://tomcat.apache.org/tomcat-7.0-doc/appdev/sample/sample.war
gsutil cp sample.war gs://gcp-hw-app-bucket
```

## 2. create MIG for backend with installed tomcat and on boot download demo application from bucket

```bash

```
