SHELL:=/bin/bash
REQUIRED_BINARIES := kubectl clusterctl
REQUIRED_KUBE_BINARIES := yq base64 kubecm
WORKING_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
                                                           #  Set to "" if you don't want to enable SSH, or are using another solution.
CLUSTER_NAME=rke2-hv-test # Name of the cluster that will be created.
NAMESPACE=default # Namespace where the cluster will be created.
RKE2_VERSION=v1.26.6+rke2r1 # Kubernetes Version
SSH_KEYPAIR=default/fulcrum # should exist in Harvester prior to applying manifest
VM_IMAGE_NAME=default/ubuntu # Should have the format <NAMESPACE>/<NAME> for an image that exists on Harvester
CONTROL_PLANE_MACHINE_COUNT=1
WORKER_MACHINE_COUNT=3
HARVESTER_CLUSTER_NAME := deathstar #! This is the cluster name by context in your kubeconfig file.
HARVESTER_ENDPOINT=10.10.0.10
VM_NETWORK=host
VM_DISK_SIZE=40Gi
CLOUD_CONFIG_SECRET=""

check-tools: ## Check to make sure you have the right tools
	$(foreach exec,$(REQUIRED_BINARIES),\
		$(if $(shell which $(exec)),,$(error "'$(exec)' not found. It is a dependency for this Makefile"))) 
check-kube-tools: ## Check to make sure you have the right tools
	$(foreach exec,$(REQUIRED_KUBE_BINARIES),\
		$(if $(shell which $(exec)),,$(error "'$(exec)' not found. It is a dependency for this Makefile")))

kind: check-tools
	$(call colorecho,"Creating KinD Cluster", 6)
	@kind create cluster --config ${WORKING_DIR}/kind/kind-cluster-with-extramounts.yaml
	
clusterctl: check-tools
	$(call colorecho,"Creating CAPI Resources", 6)
	@EXP_CLUSTER_RESOURCE_SET=true \
	CLUSTER_TOPOLOGY=true \
	clusterctl --config ${WORKING_DIR}/clusterctl.yaml init -i harvester --bootstrap rke2 --control-plane rke2

	$(call colorecho,"Waiting for RKE2 Bootstap Controller deployment...", 6)
	@kubectl rollout status deployment --timeout=90s -n rke2-bootstrap-system rke2-bootstrap-controller-manager
	$(call colorecho,"Waiting for RKE2 ControlPlane Controller deployment...", 6)
	@kubectl rollout status deployment --timeout=90s -n rke2-control-plane-system rke2-control-plane-controller-manager
	$(call colorecho,"Waiting for CAPHV Controller deployment...", 6)
	@kubectl rollout status deployment --timeout=90s -n caphv-system caphv-controller-manager

deploy: 
	$(call colorecho,"Deploying RKE2 as a Downstream Cluster", 6)
	kubectl config use-context $(HARVESTER_CLUSTER_NAME); \
	export HARVESTER_KUBECONFIG_B64=$$(kubectl config use-context $(HARVESTER_CLUSTER_NAME) &>/dev/null && kubectl config view --minify --flatten | yq '.contexts[0].name = "local"' | yq '.current-context = "local"' | base64 -w0); \
	kubectl config use-context kind-capi-test; \
	NAMESPACE=$(NAMESPACE) \
	CLUSTER_NAME=$(CLUSTER_NAME) \
	CONTROL_PLANE_MACHINE_COUNT=$(CONTROL_PLANE_MACHINE_COUNT) \
	WORKER_MACHINE_COUNT=$(WORKER_MACHINE_COUNT) \
	SSH_KEYPAIR=$(SSH_KEYPAIR) \
	VM_IMAGE_NAME=$(VM_IMAGE_NAME) \
	HARVESTER_ENDPOINT=$(HARVESTER_ENDPOINT) \
	VM_NETWORK=$(VM_NETWORK) \
	VM_DISK_SIZE=$(VM_DISK_SIZE) \
	CLOUD_CONFIG_SECRET=$(CLOUD_CONFIG_SECRET) \
	RKE2_VERSION=$(RKE2_VERSION) clusterctl generate cluster --from ${WORKING_DIR}/template/cluster_template_rke2_harvester.yaml \
	-n $(NAMESPACE) \
	$(CLUSTER_NAME) | \
	tee custom-cluster.yaml | kubectl apply -f -

# @VSPHERE_USERNAME=$(VSPHERE_USERNAME) VSPHERE_PASSWORD=$(VSPHERE_PASSWORD) VSPHERE_SERVER=$(VSPHERE_SERVER) VSPHERE_DATACENTER=$(VSPHERE_DATACENTER) VSPHERE_DATASTORE=$(VSPHERE_DATASTORE) VSPHERE_NETWORK=$(VSPHERE_NETWORK) VSPHERE_RESOURCE_POOL=$(VSPHERE_RESOURCE_POOL) VSPHERE_FOLDER=$(VSPHERE_FOLDER) VSPHERE_TEMPLATE=$(VSPHERE_TEMPLATE) CONTROL_PLANE_ENDPOINT_IP=$(CONTROL_PLANE_ENDPOINT_IP) VIP_NETWORK_INTERFACE=$(VIP_NETWORK_INTERFACE) VSPHERE_TLS_THUMBPRINT=$(VSPHERE_TLS_THUMBPRINT) VSPHERE_SSH_AUTHORIZED_KEY=$(VSPHERE_SSH_AUTHORIZED_KEY) RANCHER_URL=$(RANCHER_URL) RANCHER_VERSION=$(RANCHER_VERSION) VM_CPU_COUNT=$(VM_CPU_COUNT) VM_MEMORY_MB=$(VM_MEMORY_MB) clusterctl --config ${WORKING_DIR}/clusterctl.yaml generate cluster $(CLUSTER_NAME) \
# 	--kubernetes-version ${RKE2_VERSION} \
# 	--control-plane-machine-count ${CONTROL_PLANE_MACHINE_COUNT} \
# 	--worker-machine-count ${WORKER_MACHINE_COUNT} \
# 	--from ${WORKING_DIR}/template/cluster_template_rke2_vsphere.yaml | tee custom-cluster.yaml | kubectl apply -f -

	$(call colorecho, "Process takes 15min or so to finish; cluster should be ready in 5-7min", 5)

watch: check-tools
	@watch clusterctl describe cluster mycluster --show-machinesets --show-resourcesets  --show-templates

kube: check-kube-tools
	@kubecm delete $(CLUSTER_NAME) || true
	@kubectl get secret $(CLUSTER_NAME)-kubeconfig -o yaml | yq e '.data.value' | base64 -d > /tmp/$(CLUSTER_NAME).yaml
	@kubecm add -c -f /tmp/$(CLUSTER_NAME).yaml

destroy: check-tools
	@kubectl delete -f custom-cluster.yaml 

clean: check-tools
	kind delete cluster -n capi-test

define colorecho
@tput setaf $2
@echo $1
@tput sgr0
endef