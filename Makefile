# Parameters for the cluster, don't edit these directly, put your changes in
# local-settings.mk.

GCE_REGION?=us-central1-f
GCE_PROJECT?=unique-caldron-775
MASTER_IMAGE_NAME?=ubuntu-1604-xenial-v20161020
CLIENT_IMAGE_NAME?=ubuntu-1604-xenial-v20161020
NUM_CLIENTS?=2
PREFIX?=kubetest
MASTER_INSTANCE_TYPE?=n1-standard-4
CLIENT_INSTANCE_TYPE?=n1-standard-1
KDD?=false
-include local-settings.mk

NODE_NUMBERS:=$(shell seq -f '%02.0f' 1 $(NUM_CLIENTS))
NODE_NAMES:=$(addprefix $(PREFIX)-,$(NODE_NUMBERS))
TOKEN?=$(shell cat token)

CNI_VERSION = v1.5.6
NODE_VERSION = v1.1.0-rc3
POLICY_VERSION = v0.5.2   # Not used for KDD

token:
	echo "Creating token"
	TOKEN=$(shell ./tokengen.sh | tee token)

gce-create:
	$(MAKE) --no-print-directory deploy-master
	$(MAKE) --no-print-directory deploy-clients
	sleep 60
	$(MAKE) --no-print-directory gce-make-cluster

calico.yaml:
	if [ $(KDD) = "true" ]; \
	then cat "calico-kdd.template.yaml" | \
	  sed "s~__NODE_VERSION__~$(NODE_VERSION)~g" | \
	  sed "s~__CNI_VERSION__~$(CNI_VERSION)~g" > $@; \
	else cat "calico-etcd.template.yaml" | \
	  sed "s~__NODE_VERSION__~$(NODE_VERSION)~g" | \
	  sed "s~__POLICY_VERSION__~$(POLICY_VERSION)~g" | \
	  sed "s~__CNI_VERSION__~$(CNI_VERSION)~g" > $@; \
	fi

master-install.sh:
	cat "master-install-template.sh" | \
	  sed "s~__PYINSTALLER_URL__~$(PYINSTALLER_URL)~g" > $@;

client-config.sh:
	cat "client-config-template.sh" | \
	  sed "s~__PREFIX__~$(PREFIX)~g" > $@;

deploy-master: master-install.sh
	-gcloud compute instances create \
	  $(PREFIX)-master \
	  --zone $(GCE_REGION) \
	  --image-project ubuntu-os-cloud \
	  --image $(MASTER_IMAGE_NAME) \
	  --machine-type $(MASTER_INSTANCE_TYPE) \
	  --local-ssd interface=scsi \
	  --metadata-from-file startup-script=master-install.sh & \
	  echo "Waiting for creation of master node to finish..." && \
	  wait && \
	  echo "master node started."

deploy-clients: client-config.sh
	echo $(NODE_NAMES) | xargs -n250 | xargs -I{} sh -c 'gcloud compute instances create \
	  {} \
	  --zone $(GCE_REGION) \
	  --image-project ubuntu-os-cloud \
	  --image $(CLIENT_IMAGE_NAME) \
	  --machine-type $(CLIENT_INSTANCE_TYPE) \
	  --metadata-from-file user-data=client-config.sh; \
	  echo "Waiting for creation of worker nodes to finish..." && \
		wait && \
		echo "Worker nodes created.";'

create-master: token
	@echo Token is: $(TOKEN)
	gcloud compute ssh $(PREFIX)-master -- sudo kubeadm init --token=$(TOKEN) --pod-network-cidr=10.244.0.0/16

join-nodes: token
	@echo Token is: $(TOKEN)
	for NODE in ${NODE_NAMES}; do \
	  echo "Joining $$NODE"; \
	  gcloud compute ssh $$NODE -- sudo kubeadm join --token=$(TOKEN) $(PREFIX)-master & \
	done; \
	echo "Waiting for join of nodes to finish..."; \
	wait; \
	echo "nodes joined."

gce-make-cluster: token
	$(MAKE) --no-print-directory create-master
	$(MAKE) --no-print-directory join-nodes

gce-apply-calico: calico.yaml
	gcloud compute copy-files calico.yaml $(PREFIX)-master:~/calico.yaml
	gcloud compute ssh $(PREFIX)-master -- kubectl apply -f ~/calico.yaml
	if [ $(KDD) = "true" ]; \
	  then gcloud compute ssh $(PREFIX)-master -- \
	  kubectl create -f https://github.com/coreos/flannel/blob/master/Documentation/kube-flannel.yml?raw=true; \
	fi

gce-cleanup:
	gcloud compute instances list --zones $(GCE_REGION) -r '$(PREFIX).*' | \
	  tail -n +2 | cut -f1 -d' ' | xargs gcloud compute instances delete --zone $(GCE_REGION)

gce-forward-ports:
	@-pkill -f '8080:localhost:8080'
	bash -c 'until gcloud compute ssh $(PREFIX)-master -- date; do echo "Trying to forward ports"; sleep 1; done'
	gcloud compute ssh core@$(PREFIX)-master -- \
	-o PasswordAuthentication=no \
	-o UserKnownHostsFile=/dev/null \
	-o StrictHostKeyChecking=no \
	-L 8080:localhost:8080 \
	-L 2379:localhost:2379 \
	-L 4194:localhost:4194 \
	-L 9090:$(PREFIX)-prom:9090 \
	-L 3000:$(PREFIX)-prom:3000 \
	-o LogLevel=quiet -nNT &
	@echo
	@echo "Forwarded ports:"
	@echo "- Grafana dashboard at http://localhost:3000/dashboard/file/grafana-dash.json"
	@echo "- Prometheus at http://localhost:9090/"
	@echo "- Kubernetes' etcd at http://localhost:2379/"
	@echo "- Kubernetes' API at http://localhost:8080/"

clean:
	$(MAKE) --no-print-directory gce-cleanup
	rm -f master-install.sh client-config.sh token calico.yaml
