#!/bin/bash
#Download Helm
wget -O helm.tgz https://get.helm.sh/helm-v3.4.1-linux-amd64.tar.gz
tar -zxvf helm.tgz
mv linux-amd64/helm /usr/local/bin/helm
#Download kubectl
az aks install-cli
#Get minio cluster credentials
az aks get-credentials -g $RESOURCEGROUP -n minio
#Install minio helm chart
helm repo add minio https://helm.min.io/
wget -O values.yaml $DOWNLOADROOT/config/minio/values.yaml
helm upgrade --install --wait minio minio/minio --set accessKey=$STORAGEACCOUNTNAME --set secretKey=$STORAGEACCOUNTKEY --values values.yaml
# Get load balancer IP, once available
until [ $(kubectl get service minio -o=jsonpath='{...ip}') != "" ]; do sleep 15; done
serviceIp=$(kubectl get service minio -o=jsonpath='{...ip}')
#Configure Pod Autoscaler
kubectl autoscale deployment minio --cpu-percent=60 --min=3 --max=50
#Create output
echo \{\"loadBalancerIP\":\"$serviceIp\"\} > $AZ_SCRIPTS_OUTPUT_PATH