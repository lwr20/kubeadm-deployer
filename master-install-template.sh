#!/bin/bash
mkdir -p /var/lib/docker
mkfs.ext4 -F /dev/disk/by-id/google-local-ssd-0
mount -o discard,defaults /dev/disk/by-id/google-local-ssd-0 /var/lib/docker
chmod a+w /var/lib/docker
echo UUID=`sudo blkid -s UUID -o value /dev/disk/by-id/google-local-ssd-0` /var/lib/docker ext4 discard,defaults,[NOFAIL] 0 2 | sudo tee -a /etc/fstab

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update
# Install docker if you don't have it already.
apt-get install -y docker.io
# Allow insecure registry
cat <<EOF >> /etc/default/docker
DOCKER_OPTS="--insecure-registry jenkins-containers:5000"
EOF
service docker restart
mkdir -p /etc/calico/
cat <<EOF > /etc/calico/calicoctl.cfg
apiVersion: v1
kind: calicoApiConfig
metadata:
spec:
  datastoreType: "etcdv2"
  etcdEndpoints: "http://10.96.232.136:6666"
EOF
apt-get install -y kubelet kubeadm kubectl kubernetes-cni

# get etcdctl 2.3.7
curl -L  https://github.com/coreos/etcd/releases/download/v2.3.7/etcd-v2.3.7-linux-amd64.tar.gz -o etcd-v2.3.7-linux-amd64.tar.gz
tar xzvf etcd-v2.3.7-linux-amd64.tar.gz etcd-v2.3.7-linux-amd64/etcdctl
mv etcd-v2.3.7-linux-amd64/etcdctl .
chmod +x etcdctl
# get latest master calicoctl
curl -L  https://github.com/projectcalico/calico-containers/releases/download/v1.0.0-rc4/calicoctl -o calicoctl
chmod +x calicoctl

sudo mv calicoctl etcdctl /usr/bin
