SHELL:=/bin/bash
REQUIRED_BINARIES := kubectl clusterctl
REQUIRED_KUBE_BINARIES := yq base64 kubecm
WORKING_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
                                                           #  Set to "" if you don't want to enable SSH, or are using another solution.
CLUSTER_NAME=rke2-hv-test # Name of the cluster that will be created.
CONTROL_PLANE_MACHINE_COUNT=1
WORKER_MACHINE_COUNT=3
HARVESTER_CLUSTER_NAME := lab
HARVESTER_ENDPOINT=10.2.0.10
VM_NETWORK=lab-workload
CLOUD_CONFIG_SECRET=""

check-tools: ## Check to make sure you have the right tools
	$(foreach exec,$(REQUIRED_BINARIES),\
		$(if $(shell which $(exec)),,$(error "'$(exec)' not found. It is a dependency for this Makefile"))) 
check-kube-tools: ## Check to make sure you have the right tools
	$(foreach exec,$(REQUIRED_KUBE_BINARIES),\
		$(if $(shell which $(exec)),,$(error "'$(exec)' not found. It is a dependency for this Makefile")))

k3d: check-tools
	$(call colorecho,"Creating K3D Cluster", 6)
	@k3d cluster create
	
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
	export HARVESTER_KUBECONFIG_B64=$$(kubectl config use-context $(HARVESTER_CLUSTER_NAME) &>/dev/null && kubectl config view --minify --flatten | yq '.contexts[0].name = "$(HARVESTER_CLUSTER_NAME)"' | yq '.current-context = "$(HARVESTER_CLUSTER_NAME)"' | yq '.clusters[0].name = "$(HARVESTER_CLUSTER_NAME)"' | yq '.contexts[0].context.cluster = "$(HARVESTER_CLUSTER_NAME)"' | base64 -w0); \
	kubectl config use-context k3d-k3s-default; \
	clusterctl generate cluster --from ${WORKING_DIR}/template/rancher_rke2.yaml \
	--config ${WORKING_DIR}/clusterctl.yaml \
	$(CLUSTER_NAME) | \
	kubectl apply -f -

	$(call colorecho, "Process takes 15min or so to finish; cluster should be ready in 5-7min", 5)

watch: check-tools
	@watch clusterctl describe cluster mycluster --show-machinesets --show-resourcesets  --show-templates

kube: check-kube-tools
	@kubecm delete $(CLUSTER_NAME) || true
	@kubectl get secret $(CLUSTER_NAME)-kubeconfig -o yaml | yq e '.data.value' | base64 -d > /tmp/$(CLUSTER_NAME).yaml
	@kubecm add -c -f /tmp/$(CLUSTER_NAME).yaml

destroy: check-tools
	@kubectl delete cluster $(CLUSTER_NAME)

clean: check-tools
	@k3d cluster delete

define colorecho
@tput setaf $2
@echo $1
@tput sgr0
endef