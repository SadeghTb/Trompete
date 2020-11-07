# Install Kubernetes cluster with two master nodes via Vagrant

## Install Vagrant
```bash
$ sudo apt install virtualbox
$ sudo apt update
$ curl -O https://releases.hashicorp.com/vagrant/2.2.6/vagrant_2.2.6_x86_64.deb
$ sudo apt install ./vagrant_2.2.6_x86_64.deb
```
To verify that the installation was successful, run the following command which prints the Vagrant version:
```bash
vagrant --version
```
## Initial 
First we clone `https://github.com/coolsvap/kubeadm-vagrant` git repository.
it is a basic kubernetes cluster with one node that use kubeadm to deploy kubernetes on vagrant.
```bash
git clone https://github.com/coolsvap/kubeadm-vagrant
```
In this repository you can choose your distribution from Centos/Ubuntu ( we used Ubuntu)

We will have problem with download klubernetes apt key so we download it separetly and serve it to our vagrant machines localy.
we setup a simple HTTP server to serve it ( turn on the VPN for download it) .
``` bash
cd /home/ubuntu
wget https://packages.cloud.google.com/apt/doc/apt-key.gpg
python -m SimpleHTTPServer 8000
```
## Keepalived
we use keepalived to provide HA to our cluster and this service is responsible to change virtual ip if our main master failed.
we configure keepalive like below.
`keepalive.conf.master`
```bash
! Configuration File for keepalived
global_defs {
  router_id LVS_DEVEL
}

vrrp_script check_apiserver {
  script "/etc/keepalived/check_apiserver.sh"
  interval 3
  weight -2
  fall 10
  rise 2
}

vrrp_instance VI_1 {
    state MASTER
    interface enp0s8
    virtual_router_id 51
    priority 101
    authentication {
        auth_type PASS
        auth_pass velotiotechnologies
    }
    virtual_ipaddress {
        192.168.0.30
    }
    track_script {
        check_apiserver
    }
}
```
`keepalive.conf.master2`
```bash
! Configuration File for keepalived
global_defs {
  router_id LVS_DEVEL
}

vrrp_script check_apiserver {
  script "/etc/keepalived/check_apiserver.sh"
  interval 3
  weight -2
  fall 10
  rise 2
}

vrrp_instance VI_1 {
    state BACKUP
    interface enp0s8
    virtual_router_id 51
    priority 100
    authentication {
        auth_type PASS
        auth_pass velotiotechnologies
    }
    virtual_ipaddress {
        192.168.0.30
    }
    track_script {
        check_apiserver
    }
}

```
* set higher priority in config of master you want to be main.
* set the right interface for each master
* set main master state to MASTER and backup master to BACKUP

we need a script to understand the absense of a master apiserver to swap the virtual ip.
`check_apiserver.sh`
```bash
#!/bin/sh

errorExit() {
    echo "*** $*" 1>&2
    exit 1
}

curl --silent --max-time 2 --insecure https://localhost:6443/ -o /dev/null || errorExit "Error GET https://localhost:6443/"
if ip addr | grep -q 192.168.0.30; then
    curl --silent --max-time 2 --insecure https://192.168.0.30:6443/ -o /dev/null || errorExit "Error GET https://192.168.0.30:6443/"
fi
```

## Install Helm and using it to deploy application
All of these steps are done by `helm.sh` so dont need to run these command.
### Download Helm
```bash
wget https://get.helm.sh/helm-v2.16.0-linux-amd64.tar.gz
```
### Install Helm
``` bash
$ tar -xvf helm-v2.16.0-linux-amd64.tar.gz
$ cd linux-amd64/
$ sudo cp helm /usr/local/bin/
$ helm version --short --client
```
### Install Tiller
We will install the server-side component (tiller). But we will first need to set up a service account and clusterrolebinding. To create the service account “tiller” type the following :
```bash
$ kubectl -n kube-system create serviceaccount tiller
```
Next we will create the role binding
```bash
$ kubectl -n kube-system create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
```
We can check that the clusterrolebinding was created.
```bash
$ kubectl get clusterrolebinding tiller
NAME     AGE
tiller   65s
```
### Initializing Helm
```bash
$ helm init --service-account tiller
```
After applying the changes we should see a pod was created for tiller.
```bash
vagrant@kmaster:~/linux-amd64$ kubectl get pods -n kube-system
NAME                                      READY   STATUS    RESTARTS   AGE
calico-kube-controllers-7b9dcdcc5-fttk7   1/1     Running   1          43h
calico-node-6jpjv                         1/1     Running   1          43h
calico-node-bc8db                         1/1     Running   1          43h
calico-node-qrxjw                         1/1     Running   1          43h
coredns-5644d7b6d9-8vflt                  1/1     Running   1          43h
coredns-5644d7b6d9-spp2d                  1/1     Running   1          43h
etcd-kmaster                              1/1     Running   1          43h
kube-apiserver-kmaster                    1/1     Running   1          43h
kube-controller-manager-kmaster           1/1     Running   1          43h
kube-proxy-bd7fz                          1/1     Running   1          43h
kube-proxy-hdfwx                          1/1     Running   1          43h
kube-proxy-wdsng                          1/1     Running   1          43h
kube-scheduler-kmaster                    1/1     Running   1          43h
tiller-deploy-68cff9d9cb-46r9w            1/1     Running   0          32s
```
### Install helm and application
We use `helm.sh` script to install our application using helm.
```bash
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
```
* We remove taint on master nodes to allow pods to be schedule on this node because in this state there is no worker node up yet.
* Create helm init file with `helm create nginx`
* Copy our configs in created helm folder ( we use sadeghtb/nginx-simple:2.0 image )
* Package our configs that placed in helm folder and structure
* We wait 5m to triller be up then we install our package on our kubernetes cluster

### Application image
Application should have a version and a health check api.
We use nginx simple image and add our health check api to its config.
add this section to `default.conf` for helath check api
```bash
    location /nginx-health {
        access_log off;
        return 200 "healthy\n";
    }
```
Nginx will return its version in `/version`.
build our image with this config and then push it to docker hub.
```bash
FROM nginx
COPY nginx.default /etc/nginx/conf.d/default.conf
```

## Configure Vagrant related files
We have two files in Ubuntu directory in first place. `Vagrantfile` that determine Vagrant configs and `install-ubuntu.sh` ( it is for initial configs for all hosts )
### Customize install-ubuntu.sh file
we change `install-ubuntu.sh` file like below :
```bash
#!/bin/sh

# Source: http://kubernetes.io/docs/getting-started-guides/kubeadm/
echo "nameserver 185.51.200.2\nnameserver 178.22.122.100\n" > /etc/resolv.conf
apt-get remove -y docker.io kubelet kubeadm kubectl kubernetes-cni
apt-get autoremove -y
systemctl daemon-reload
curl http://192.168.0.25:8000/apt-key.gpg | apt-key add -
#curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update
apt-get install -y docker.io kubelet kubeadm kubectl kubernetes-cni
systemctl enable kubelet && systemctl start kubelet

cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "storage-driver": "overlay2"
}
EOF

mkdir -p /etc/systemd/system/docker.service.d

# Restart docker.
systemctl daemon-reload


systemctl enable docker && systemctl start docker

docker info | grep overlay
docker info | grep systemd

```
* we add this line to our initial config because we need to use shecan dns in all of our machines to be able to download kubernetes and docker packages.
```bash
echo "nameserver 185.51.200.2\nnameserver 178.22.122.100\n" > /etc/resolv.conf
```
* we use local http server to download `apt-key.gpg` that we set up in Initial part.
```bash
curl http://192.168.0.25:8000/apt-key.gpg | apt-key add -
```

Finally we need to edit `Vagrantfile` based on our needs and architecture.
### Customize Vagrantfile 
It is the main file and vagrant only read this file to create machines. so it is our main file and we will describe our changes in diffrent parts ( all of the remainig steps are for `Vagrantfile` )
#### Define Variables
```ini
BOX_IMAGE = "ubuntu/xenial64" ## define our machines image 
SETUP_MASTER = true 
SEC_MASTER = true
SETUP_NODES = true
NODE_COUNT = 2 # number of worker nodes
MASTER_IP = "192.168.0.10"
SEC_MASTER_IP = "192.168.0.20"
VIRTUAL_IP = "192.168.0.30" # Virtual IP we use for HA with keepalived
NODE_IP_NW = "192.168.0." # worker nodes network
#NODE_IP_NW = "192.168.122."
POD_NW_CIDR = "10.244.0.0/16"
#Generate new using steps in README
KUBETOKEN = "b029ee.968a33e8d8e6bb0d" # we can generate this token and replace that with this value but we use this value
```
#### Keepalived
Install Keepalived on master nodes and move configs to the correct folder. 
```ini
$resetkeepalived = <<RESETKEEPALIVED
mv /tmp/keepalived.conf /etc/keepalived
mv /tmp/check_apiserver.sh /etc/keepalived
service keepalived restart
RESETKEEPALIVED

$installkeepalived = <<INSTALLKEEPALIVED
mkdir /tmp/etcd
chmod -R 777 /tmp/etcd
apt update
apt install keepalived -y
INSTALLKEEPALIVED
```
#### First Master
First master config script.
```ini
$kubemasterscript = <<SCRIPT
apt-get install sshpass
ip route delete 0.0.0.0/0 via 10.0.2.2 dev enp0s3 && ip route add 0.0.0.0/0 via 192.168.0.1 dev enp0s8
kubeadm reset
kubeadm init  --control-plane-endpoint=#{VIRTUAL_IP} --apiserver-advertise-address=#{MASTER_IP} --pod-network-cidr=#{POD_NW_CIDR} --token #{KUBETOKEN} --token-ttl 0

mkdir -p $HOME/.kube
sudo cp -Rf /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
for pkiFiles in ca.crt ca.key sa.key sa.pub front-proxy-ca.crt front-proxy-ca.key
do
	sshpass -p 'password' scp -o "StrictHostKeyChecking no" -qpr /etc/kubernetes/pki/${pkiFiles} ubuntu@192.168.0.25:/home/ubuntu/kubeadm-vagrant/Ubuntu
done

for etcdFiles in ca.crt ca.key
do
	sshpass -p 'password' scp -o "StrictHostKeyChecking no" -qpr /etc/kubernetes/pki/etcd/${etcdFiles} ubuntu@192.168.0.25:/home/ubuntu/kubeadm-vagrant/Ubuntu/etcd
done
sshpass -p 'password' scp -o "StrictHostKeyChecking no" -r /etc/kubernetes/admin.conf ubuntu@192.168.0.25:/home/ubuntu/kubeadm-vagrant/Ubuntu
mv /tmp/helm.sh /home/vagrant
chmod +x /home/vagrant/helm.sh
sudo /home/vagrant/helm.sh
SCRIPT
```
* Install sshpass to pass password with ssh command
* Add correct default route ( describe the reason on important tips at the end of the doc)
* Install kubernetes with kubeadm
* Use flannel as cni
* We need to copy some certificates to second master so it can join the cluster. because of the second master is not created yet we copy these certificates to the host. we will pass these certs to second master.
* Also we pass helm installation script to master and make it executable ( we will describe `helm.sh` later) .
#### Second Master 
Second master config script to join the first master
```ini
$kubemastersecond = <<SCRIPTSECONDMASTER
mkdir /etc/kubernetes/pki
mkdir /etc/kubernetes/pki/etcd
mv /tmp/admin.conf /etc/kubernetes
mv /tmp/ca.crt /etc/kubernetes/pki
mv /tmp/ca.key /etc/kubernetes/pki
mv /tmp/sa.key /etc/kubernetes/pki
mv /tmp/sa.pub /etc/kubernetes/pki
mv /tmp/front-proxy-ca.crt /etc/kubernetes/pki
mv /tmp/front-proxy-ca.key /etc/kubernetes/pki
mv /tmp/etcd/ca.crt /etc/kubernetes/pki/etcd
mv /tmp/etcd/ca.key /etc/kubernetes/pki/etcd
     
ip route delete 0.0.0.0/0 via 10.0.2.2 dev enp0s3 && ip route add 0.0.0.0/0 via 192.168.0.1 dev enp0s8
kubeadm reset
kubeadm join --token #{KUBETOKEN} #{VIRTUAL_IP}:6443 --discovery-token-unsafe-skip-ca-verification --control-plane --apiserver-advertise-address=#{SEC_MASTER_IP}

SCRIPTSECONDMASTER
```
#### Worker nodes
Worker nodes config script
```ini
$kubeminionscript = <<MINIONSCRIPT
ip route delete 0.0.0.0/0 via 10.0.2.2 dev enp0s3 && ip route add 0.0.0.0/0 via 192.168.0.1 dev enp0s8
kubeadm reset
kubeadm join --token #{KUBETOKEN} #{VIRTUAL_IP}:6443 --discovery-token-unsafe-skip-ca-verification

MINIONSCRIPT
```
#### Machines Base Configs
All machines description are below. it contains hostname, network inetrfaces, ip, spec, image, scripts to run during deploying each machine, files to copy to deploying machine.  
```ini
Vagrant.configure("2") do |config|
  config.vm.box = BOX_IMAGE
  config.vm.box_check_update = false

  config.vm.provider "virtualbox" do |l|
    l.cpus = 2
    l.memory = "2048"
  end

  config.vm.provision :shell, :path => "install-ubuntu.sh"

  if SETUP_MASTER
    config.vm.define "master" do |subconfig|
      subconfig.vm.hostname = "master"
      subconfig.vm.network :public_network, ip: MASTER_IP
      subconfig.vm.provider :virtualbox do |vb|
        vb.customize ["modifyvm", :id, "--cpus", "2"]
        vb.customize ["modifyvm", :id, "--memory", "2048"]
      end
      subconfig.vm.provision :shell, inline: $installkeepalived
      subconfig.vm.provision "file", source: "keepalived.conf.master", destination: "/tmp/keepalived.conf"
      subconfig.vm.provision "file", source: "check_apiserver.sh", destination: "/tmp/check_apiserver.sh"
      subconfig.vm.provision "file", source: "nginx-pod.yaml", destination: "/tmp/nginx-pod.yaml"
      subconfig.vm.provision "file", source: "helm.sh", destination: "/tmp/helm.sh"
      subconfig.vm.provision :shell, inline: $resetkeepalived
      subconfig.vm.provision :shell, inline: $kubemasterscript
    end
  end

  if SEC_MASTER
    config.vm.define "master2" do |subconfig|
      subconfig.vm.hostname = "master2"
      subconfig.vm.network :public_network, ip: SEC_MASTER_IP
      subconfig.vm.provider :virtualbox do |vc|
        vc.customize ["modifyvm", :id, "--cpus", "2"]
        vc.customize ["modifyvm", :id, "--memory", "2048"]
      end
      subconfig.vm.provision :shell, inline: $installkeepalived
      subconfig.vm.provision "file", source: "keepalived.conf.master2", destination: "/tmp/keepalived.conf"
      subconfig.vm.provision "file", source: "check_apiserver.sh", destination: "/tmp/check_apiserver.sh"
      subconfig.vm.provision "file", source: "ca.crt", destination: "/tmp/ca.crt"
      subconfig.vm.provision "file", source: "ca.key", destination: "/tmp/ca.key"
      subconfig.vm.provision "file", source: "sa.key", destination: "/tmp/sa.key"
      subconfig.vm.provision "file", source: "sa.pub", destination: "/tmp/sa.pub"
      subconfig.vm.provision "file", source: "front-proxy-ca.crt", destination: "/tmp/front-proxy-ca.crt"
      subconfig.vm.provision "file", source: "front-proxy-ca.key", destination: "/tmp/front-proxy-ca.key"
      subconfig.vm.provision "file", source: "etcd/ca.key", destination: "/tmp/etcd/ca.key"
      subconfig.vm.provision "file", source: "etcd/ca.crt", destination: "/tmp/etcd/ca.crt"
      subconfig.vm.provision "file", source: "admin.conf", destination: "/tmp/admin.conf"
      subconfig.vm.provision :shell, inline: $resetkeepalived
      subconfig.vm.provision :shell, inline: $kubemastersecond

    end
  end

  
  if SETUP_NODES
    (1..NODE_COUNT).each do |i|
      config.vm.define "node#{i}" do |subconfig|
        subconfig.vm.hostname = "node#{i}"
        subconfig.vm.network :public_network, ip: NODE_IP_NW + "#{i + 50}"
        subconfig.vm.provision :shell, inline: $kubeminionscript
      end
    end
  end
end
```
## Make everything work
After all of these configs we can provision machines by this command.
```bash
vagrant up
```
Important Tips :
* Vagrant uses a nat interface to ssh to each machine and default route is set to this insterface. if we dont change this default route to our network it will cause problem for kubernetes cluster and cluster will use that nat interface to setup kubernetes components ( kubernetes use interface which have default route )
* Vagrant should create its nat interface to connect to machines so we cant force Vagrant not to create it. this force will cause connection problem for porvision machines. because of this, Vagrant its not good choice for situation with multiple machines because most of application listen on the first interface and with Vagrant this interface is for Vagrant and not accessible from other machines. 
* Vagrant doesnt have permission to copy files from host to folders owned by root or other users so we need to copy them to /tmp and then copy them from there to our desire destination.
## Questions 
1. describe your design choices :
	We give each node an interface to communicate with each other and to access the internet. We use keepalived for HA purpose it will change Virtual ip if main master be unreachable. All of worker nodes and master nodes components talk to that virtual ip so when that ip switch from one master to another there will be no problem in connection.

2. describe a solution for zero-downtime deployment with Kubernetes :
    We can use rolling updates for this purpose. it incrementally updating Pods instances with new ones and when all of users that works with old pods disconnected all of old pods will be replaced by new ones and new users will connect to our new version of application. We also can use A/B testing strategy to make sure our new pods are doing good by routing some percent of our traffic to these new pods. Then if everything gone fine then replace all old pods with new version. We can reach these purposes with Jenkins.
