SHELL:=/bin/bash
REQUIRED_BINARIES := kubectl clusterctl
REQUIRED_KUBE_BINARIES := yq base64 kubecm
WORKING_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

# vsphere details
VSPHERE_CRED_FILE=/Volumes/BIGBOY/keys/vsphere_creds.yaml							# If you hardcode your own username/password, you don't need this
VSPHERE_USERNAME 			:= $(shell yq e .vsphere_username ${VSPHERE_CRED_FILE}) # feel free to remove this and manually set your own
VSPHERE_PASSWORD 			:= $(shell yq e .vsphere_password ${VSPHERE_CRED_FILE}) # feel free to remove this and manually set your own
VSPHERE_SERVER 				:= "10.0.0.5"                                           # The vCenter server IP or FQDN
VSPHERE_DATACENTER 			:= "Datacenter"                         				# The vSphere datacenter to deploy the management cluster on
VSPHERE_DATASTORE 			:= "datastore1"                         				# The vSphere datastore to deploy the management cluster on
VSPHERE_NETWORK 			:= "rgs-network"                                 		# The VM network to deploy the management cluster on
VSPHERE_RESOURCE_POOL 		:= "*/Resources"                          				# The vSphere resource pool for your VMs
VSPHERE_FOLDER 				:= "ranchermcm"                                         # The VM folder for your VMs. Set to "" to use the root vSphere folder
VSPHERE_TEMPLATE 			:= "ubuntu_20.04"                         				# The VM template to use for your management cluster.
CONTROL_PLANE_ENDPOINT_IP 	:= "10.1.1.3"                    						# the IP that kube-vip is going to use as a control plane endpoint
VIP_NETWORK_INTERFACE 		:= "eth0"                            					# The interface that kube-vip should apply the IP to. Omit to tell kube-vip to autodetect the interface.

VSPHERE_TLS_THUMBPRINT 		:= $(shell echo | openssl s_client -connect $(strip $(VSPHERE_SERVER)):443 -prexit 2>/dev/null | openssl x509 -fingerprint -noout -sha1 | cut -d= -f2-)
VSPHERE_SSH_AUTHORIZED_KEY 	:= "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDZk5zkAj2wbSs1r/AesCC7t6CtF6yxmCjlXgzqODZOujVscV6PZzIti78dIhv3Yqtii/baFH0PfqoHZk9eayjZMcp+K+6bi4lSwszzDhV3aGLosPRNOBV4uT+RToEmiXwPtu5rJSRAyePu0hdbuOdkaf0rGjyUoMbqJyGuVIO3yx/+zAuS8hFGeV/rM2QEhzPA4QiR40OAW9ZDyyTVDU0UEhwUNQESh+ZM2X9fe5VIxNZcydw1KGwzj8t+6WuYBFvPKYR5sylAnocBWzAGKh+zHgZU5O5TwC1E92uPgUWNwMoFdyZRaid0sKx3O3EqeIJZSqlfoFhz3Izco+QIx4iqXU9jIVFtnTb9nCN/boXx7uhCfdaJ0WdWQEQx+FX092qE6lfZFiaUhZI+zXvTeENqVfcGJSXDhDqDx0rbbpvXapa40XZS/gk0KTny2kYXBATsUwZqmPpZF9njJ+1Hj/KSNhFQx1LcIQVvXP+Ie8z8MQleaTTD0V9+Zkw2RBkVPYc5Vb8m8XCy1xf4DoP6Bmb4g3iXS17hYQEKj1bfBMbDfZdexbSPVOUPXUMR2aMxz8R3OaswPimLmo0uPiyYtyVQCuJu62yrao33knVciV/xlifFsqrNDgribDNr4RKnrIX2eyszCiSv2DoZ6VeAhg8i6v6yYL7RhQM31CxYjnZK4Q=="
                                                              #  Set to "" if you don't want to enable SSH, or are using another solution.

CONTROL_PLANE_MACHINE_COUNT := 3
WORKER_MACHINE_COUNT        := 1
RKE2_VERSION                := v1.25.11+rke2r1
VM_CPU_COUNT                := 4
VM_MEMORY_MB                := 16384

RANCHER_URL 				:= rancher.mycluster.com  								# this needs to be a valid URL, however you can statically set this in /etc/hosts if necessary
RANCHER_VERSION 			:= 2.7.4
CLUSTER_NAME                := mycluster

check-tools: ## Check to make sure you have the right tools
	$(foreach exec,$(REQUIRED_BINARIES),\
		$(if $(shell which $(exec)),,$(error "'$(exec)' not found. It is a dependency for this Makefile"))) 
check-kube-tools: ## Check to make sure you have the right tools
	$(foreach exec,$(REQUIRED_KUBE_BINARIES),\
		$(if $(shell which $(exec)),,$(error "'$(exec)' not found. It is a dependency for this Makefile")))
	
clusterctl: check-tools
	@export EXP_CLUSTER_RESOURCE_SET=true
	@export CLUSTER_TOPOLOGY=true

	$(call colorecho,"Creating CAPV Resources", 6)
	@VSPHERE_USERNAME=$(VSPHERE_USERNAME) VSPHERE_PASSWORD=$(VSPHERE_PASSWORD) clusterctl --config ${WORKING_DIR}/clusterctl.yaml init -i vsphere --bootstrap rke2 --control-plane rke2

	$(call colorecho,"Waiting for RKE2 Bootstap Controller deployment...", 6)
	@kubectl rollout status deployment --timeout=90s -n rke2-bootstrap-system rke2-bootstrap-controller-manager
	$(call colorecho,"Waiting for RKE2 ControlPlane Controller deployment...", 6)
	@kubectl rollout status deployment --timeout=90s -n rke2-control-plane-system rke2-control-plane-controller-manager
	$(call colorecho,"Waiting for CAPV Controller deployment...", 6)
	@kubectl rollout status deployment --timeout=90s -n capv-system capv-controller-manager

deploy: 
	$(call colorecho,"Deploying RKE2 as a Downstream Cluster", 6)
	@VSPHERE_USERNAME=$(VSPHERE_USERNAME) VSPHERE_PASSWORD=$(VSPHERE_PASSWORD) VSPHERE_SERVER=$(VSPHERE_SERVER) VSPHERE_DATACENTER=$(VSPHERE_DATACENTER) VSPHERE_DATASTORE=$(VSPHERE_DATASTORE) VSPHERE_NETWORK=$(VSPHERE_NETWORK) VSPHERE_RESOURCE_POOL=$(VSPHERE_RESOURCE_POOL) VSPHERE_FOLDER=$(VSPHERE_FOLDER) VSPHERE_TEMPLATE=$(VSPHERE_TEMPLATE) CONTROL_PLANE_ENDPOINT_IP=$(CONTROL_PLANE_ENDPOINT_IP) VIP_NETWORK_INTERFACE=$(VIP_NETWORK_INTERFACE) VSPHERE_TLS_THUMBPRINT=$(VSPHERE_TLS_THUMBPRINT) VSPHERE_SSH_AUTHORIZED_KEY=$(VSPHERE_SSH_AUTHORIZED_KEY) RANCHER_URL=$(RANCHER_URL) RANCHER_VERSION=$(RANCHER_VERSION) VM_CPU_COUNT=$(VM_CPU_COUNT) VM_MEMORY_MB=$(VM_MEMORY_MB) clusterctl --config ${WORKING_DIR}/clusterctl.yaml generate cluster $(CLUSTER_NAME) \
		--kubernetes-version ${RKE2_VERSION} \
		--control-plane-machine-count ${CONTROL_PLANE_MACHINE_COUNT} \
		--worker-machine-count ${WORKER_MACHINE_COUNT} \
		--from ${WORKING_DIR}/template/cluster_template_rke2_vsphere.yaml | tee custom-cluster.yaml | kubectl apply -f -

	$(call colorecho, "Process takes 15min or so to finish; cluster should be ready in 5-7min", 5)

watch: check-tools
	@watch clusterctl describe cluster mycluster --show-machinesets --show-resourcesets  --show-templates

kube: check-kube-tools
	@kubecm delete $(CLUSTER_NAME) || true
	@kubectl get secret $(CLUSTER_NAME)-kubeconfig -o yaml | yq e '.data.value' | base64 -d > /tmp/$(CLUSTER_NAME).yaml
	@kubecm add -c -f /tmp/$(CLUSTER_NAME).yaml

destroy: check-tools
	kubectl delete -f custom-cluster.yaml 

define colorecho
@tput setaf $2
@echo $1
@tput sgr0
endef