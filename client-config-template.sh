#!/bin/bash

curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial-unstable main
EOF
apt-get update
# Install docker if you don't have it already.
apt-get install -y docker.io

# Allow insecure registry
cat <<EOF >> /etc/default/docker
DOCKER_OPTS="--insecure-registry jenkins-containers:5000"
EOF
service docker restart
apt-get install -y kubelet kubeadm kubectl kubernetes-cni
