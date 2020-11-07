#!/bin/bash

mkdir /home/vagrant/.kube
sudo cp /root/.kube/config /home/vagrant/.kube
sudo chown -R vagrant:vagrant /home/vagrant/.kube
wget https://get.helm.sh/helm-v2.16.0-linux-amd64.tar.gz
tar -xvf helm-v2.16.0-linux-amd64.tar.gz
cd linux-amd64/
sudo cp helm /usr/local/bin/
kubectl -n kube-system create serviceaccount tiller
kubectl -n kube-system create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
kubectl taint nodes master node-role.kubernetes.io/master:NoSchedule- # let master host the pods
helm init --service-account tiller
helm repo update
mkdir /home/vagrant/helm
cd /home/vagrant/helm
helm create nginx
cd nginx && rm -rf charts && cd templates && rm -rf * && cd ..
printf "pod:\n  fullname: nginxam\n  image: sadeghtb/nginx-simple:2.0\n" >> values.yaml
mv /tmp/nginx-pod.yaml /home/vagrant/helm/nginx/templates
helm package /home/vagrant/helm/nginx
sleep 5m # wait for tiller to be up
helm install nginx-0.1.0.tgz
