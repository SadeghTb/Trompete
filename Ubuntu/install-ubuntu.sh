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


