SHELL:=/bin/bash
REQUIRED_BINARIES := kubectl kubectx kubecm clusterctl yq base64 kind
WORKING_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

# vsphere details
VSPHERE_CRED_FILE=/Volumes/BIGBOY/keys/vsphere_creds.yaml
VSPHERE_USERNAME := $(shell yq e .vsphere_username ${VSPHERE_CRED_FILE})
VSPHERE_PASSWORD := $(shell yq e .vsphere_password ${VSPHERE_CRED_FILE})

CLUSTER_NAME=mycluster

check-tools: ## Check to make sure you have the right tools
	$(foreach exec,$(REQUIRED_BINARIES),\
		$(if $(shell which $(exec)),,$(error "'$(exec)' not found. It is a dependency for this Makefile")))
	
kind: check-tools
	$(call colorecho,"Deploying Rancher via CAPI to vSphere", 6)
	$(call colorecho,"Creating KinD Cluster", 6)
# kind create cluster --config "$(WORKING_DIR)/kind/kind-cluster-with-extramounts.yaml"
# kubectl rollout status deployment coredns -n kube-system --timeout=90s


clusterctl:
	export EXP_CLUSTER_RESOURCE_SET=true
	export CLUSTER_TOPOLOGY=true

	$(call colorecho,"Creating CAPV Resources", 6)
	VSPHERE_USERNAME=$(VSPHERE_USERNAME) VSPHERE_PASSWORD=$(VSPHERE_PASSWORD) clusterctl --config ${WORKING_DIR}/clusterctl.yaml init -i vsphere --bootstrap rke2 --control-plane rke2

# TODO: wait

mgmt: check-tools
	$(call colorecho,"Deploying RKE2 as a Downstream Cluster", 6)
	VSPHERE_USERNAME=$(VSPHERE_USERNAME) VSPHERE_PASSWORD=$(VSPHERE_PASSWORD) clusterctl --config ${WORKING_DIR}/clusterctl.yaml generate cluster $(CLUSTER_NAME) \
		--kubernetes-version v1.25.11+rke2r1 \
		--control-plane-machine-count 1 \
		--worker-machine-count 3 \
		--from ${WORKING_DIR}/template/cluster_template_rke2_vsphere.yaml | tee custom-cluster.yaml | kubectl apply -f -
# TODO: wait

kube: check-tools
	kubecm delete $(CLUSTER_NAME) || true
	kubectl get secret $(CLUSTER_NAME)-kubeconfig -o yaml | yq e '.data.value' | base64 -d > /tmp/$(CLUSTER_NAME).yaml
	kubecm add -c -f /tmp/$(CLUSTER_NAME).yaml

mgmt-destroy: check-tools
	kubectl delete -f custom-cluster.yaml 
	kubecm delete $(CLUSTER_NAME) || true

define colorecho
@tput setaf $2
@echo $1
@tput sgr0
endef
define randompassword
${shell head /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 13}
endef