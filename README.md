# Bootstrapping Rancher into vSphere using ClusterAPI

This doc is a basic howto around this small PoC. I won't cover deep technical details but will touch a few topics to put things in context. This PoC lays out a way to deploy Rancher onto RKE2 into an infrastructure. I chose vSphere as I have a stack running in my lab. This PoC assumes internet access, it will not work as-is in an airgap (though CAPI does support this).

## TL;DR
If you already understand CAPI and don't need the background, jump down to [Tools Needed](#tools-needed). 

## The Problem

Bootstrapping a management cluster in Kubernetes is probably the single hardest part of the process to reach a Day1 status on a platform. This is due to the high amount of variance between both the environments it is being deployed to and the process for delivering it. Rancher is capable of making this process less painful as it provides many ways to deploy and supports a large amount of environments. 

However, doing things the 'right' way will include some kind of infrastructure tool like [Hashicorp's Terraform](https://www.terraform.io/). It's important because when deploying infrastructure (or paving it as we used to say at Pivotal), that infrastructure needs to be repeatable and thus defined via Infrastructure as Code (IaC) as opposed to a manual process. This is one of the fundamental principles of platform engineering.

One of the lesser discussed topics in platform engineering is the inherent difficulty created when working with a heterogeneous set of tools. Terraform is an amazing tool but it has to cater to deploying infrastructure as a general concept, not necessarily scoped specifically for Kubernetes. Other tools like Ansible are the same way but even more variant as it is just a remote script runner, lacking any declarative capability.

[ClusterAPI](https://cluster-api.sigs.k8s.io/), a K8S subproject, brings the capability of provisioning Kubernetes-centric infrastructure into a large variety of infrastructure providers. And it does this by using the same language, processing, and scheduling that one uses for all manner of other Kubernetes objects. Being able to define your infrastructure declaratively using the same language you use to define a container-based application and thus manage it using the same tools and processes, is a very powerful capability.

Rancher has had ClusterAPI capabilities before ClusterAPI was a real thing, but when bootstrapping it as it is still a Kubernetes application, one was left in the same position as other K8S distros: You still have to build the infrastructure first.

## The Solution

Using ClusterAPI and built-in RKE2 capabilities, we can deploy a downstream RKE2 cluster and install Rancher on it using only tools that speak the Kubernetes language/API. We can use Kubernetes to install Kubernetes! We'll define our infrastructure, Ubuntu-based RKE2 nodes/cluster on vSphere VMs in this case, using ClusterAPI; and we will use `HelmChart` CRDs defined in RKE2 to deliver `cert-manager` and `rancher` helm charts to the new cluster.

We have to start from somewhere though and there are two ways to do that, both are easy but I feel one is superior. Start by installing [Rancher Desktop](https://rancherdesktop.io/). This uses a small VM to spin up an instance of K3S and underhood is using containerd. It runs on most OS's (Linux, Mac, and Windows included). You merely need to get access to a shell to run some K8S commands against it.

The second way is using KinD which is 'Kubernetes in Docker'. I've tested both cases and they work great, but Rancher Dekstop has a more polished experience and is more friendly to folks not accustomed to a terminal (though it does support terminals just fine).

## Tools Needed
The toolset is very minimal, you don't even need `helm` (yes, you read that correctly):
* Rancher Desktop - see [here](https://rancherdesktop.io/), this will install `kubectl`
* clusterctl - see [here](https://cluster-api.sigs.k8s.io/user/quick-start#install-clusterctl) for docs to install this tool in your OS
* Make - This is installed by default in Linux and MacOS, you will need to install it in Windows.
* yq - see [here](https://github.com/mikefarah/yq) - this is much like jq but tailored to yaml, **unnecessary unless you are extracting your kubeconfig using the `kube` target in my Makefile**
* base64 - You likely already have this installed if using MacOS or Linux, but Windows users will need to install it most likely. WSL2 recommended if you're in the Windows world! **Unneccessary if you're not planning on using `kubectl` on your new cluster**
* kubecm - This is what I use to merge kube contexts, it's an amazing tool located [here](https://kubecm.cloud/)
* vsphere - you'll need a running vSphere setup. Too deep of a topic to cover, but I will be porting this to work in AWS and Kubevirt soon. You also need a VM template that supports cloud-init and vmware data sources. This demo also expects the network you choose is using DHCP and the VIP chosen as a variable is a static IP in the same network

## Setup
The only real setup here is to define your vSphere details in the Makefile and choose a cluster name (or leave it default). You'll also want to set the rancher hostname in the Makefile. If you don't have control over DNS entries, feel free to make up something and just edit your `/etc/hosts` file temporarily.

## Install
Ensure your kubecontext is pointed at your `Rancher Desktop` cluster. If you just installed Rancher Desktop, it will already be set for you. Use `kubectl config get-contexts` to check:
```console
> kubectl config get-contexts
CURRENT   NAME                CLUSTER              AUTHINFO             NAMESPACE
          deathstar           local                local                
*         rancher-desktop     rancher-desktop      rancher-desktop      
          rancher-harvester   default-5cgbgfc8ht   default-5cgbgfc8ht   
          rke2                default              default            
```

Mine is already set, but if I needed to change it, I could use `kubectl config use-context rancher-desktop`. Now I can inspect the cluster to ensure it is running properly:
```console
> kc get po -A
NAMESPACE     NAME                                      READY   STATUS      RESTARTS   AGE
kube-system   local-path-provisioner-69dff9496c-xgm9q   1/1     Running     0          7m26s
kube-system   coredns-8b9777675-bkn9p                   1/1     Running     0          7m26s
kube-system   helm-install-traefik-crd-pxhxj            0/1     Completed   0          7m26s
kube-system   metrics-server-854c559bd-h4dfv            1/1     Running     0          7m26s
kube-system   svclb-traefik-ad611b87-t2fn2              2/2     Running     0          6m55s
kube-system   traefik-66fd46ccd-dr52r                   1/1     Running     0          6m55s
kube-system   helm-install-traefik-6pvnt                0/1     Completed   2          7m26s
```

Looks good! Let's deploy! Run the Makefile using the `deploy` target.

```console
> make deploy
Creating CAPV Resources
Fetching providers
Installing cert-manager Version="v1.12.2"
Waiting for cert-manager to be available...
Installing Provider="cluster-api" Version="v1.5.0" TargetNamespace="capi-system"
Installing Provider="bootstrap-rke2" Version="v0.1.1" TargetNamespace="rke2-bootstrap-system"
Installing Provider="control-plane-rke2" Version="v0.1.1" TargetNamespace="rke2-control-plane-system"
Installing Provider="infrastructure-vsphere" Version="v1.8.0" TargetNamespace="capv-system"

Your management cluster has been initialized successfully!

You can now create your first workload cluster by running the following:

  clusterctl generate cluster [name] --kubernetes-version [version] | kubectl apply -f -

Waiting for RKE2 Bootstap Controller deployment...
deployment "rke2-bootstrap-controller-manager" successfully rolled out
Waiting for RKE2 ControlPlane Controller deployment...
deployment "rke2-control-plane-controller-manager" successfully rolled out
Waiting for CAPV Controller deployment...
deployment "capv-controller-manager" successfully rolled out
Deploying RKE2 as a Downstream Cluster
cluster.cluster.x-k8s.io/mycluster created
vspherecluster.infrastructure.cluster.x-k8s.io/mycluster created
rke2controlplane.controlplane.cluster.x-k8s.io/mycluster-control-plane created
vspheremachinetemplate.infrastructure.cluster.x-k8s.io/mycluster created
machinedeployment.cluster.x-k8s.io/worker-md-0 created
vspheremachinetemplate.infrastructure.cluster.x-k8s.io/mycluster-worker created
rke2configtemplate.bootstrap.cluster.x-k8s.io/mycluster-agent created
secret/mycluster created
secret/rancher-namespace created
clusterresourceset.addons.cluster.x-k8s.io/mycluster-rancher-crs-0 created
secret/rancher-helmchart created
secret/certmanager-helmchart created
Process takes 15min or so to finish; cluster should be ready in 5-7min
```

And that's it! If you wish to inspect everything as it works, use the `kube` target with make:
```console
> make kube
「mycluster」do not exit.
Error: nothing deleted！

...

Add Context: mycluster 
「/tmp/mycluster.yaml」 write successful!
+------------+----------------------+-----------------------+-----------------------+-----------------------------------+--------------+
|   CURRENT  |         NAME         |        CLUSTER        |          USER         |               SERVER              |   Namespace  |
+============+======================+=======================+=======================+===================================+==============+
|            |       deathstar      |         local         |         local         |   https://10.10.0.10/k8s/cluster  |    default   |
|            |                      |                       |                       |              s/local              |              |
+------------+----------------------+-----------------------+-----------------------+-----------------------------------+--------------+
|            |       mycluster      |       mycluster       |    mycluster-admin    |       https://10.1.1.3:6443       |    default   |
+------------+----------------------+-----------------------+-----------------------+-----------------------------------+--------------+
|      *     |    rancher-desktop   |    rancher-desktop    |    rancher-desktop    |       https://127.0.0.1:6443      |    default   |
+------------+----------------------+-----------------------+-----------------------+-----------------------------------+--------------+
|            |   rancher-harvester  |   default-5cgbgfc8ht  |   default-5cgbgfc8ht  |      https://10.10.5.10:6443      |    default   |
+------------+----------------------+-----------------------+-----------------------+-----------------------------------+--------------+
|            |         rke2         |        default        |        default        |       https://10.1.1.4:6443       |    default   |
+------------+----------------------+-----------------------+-----------------------+-----------------------------------+--------------+
```

For inspecting progress, I would check the logs for the capv controller to see vsphere events (if your creds or config around vsphere is wrong, this is where you would see the errors) and inspect the two RKE2 controllers logs for bootstrap and control plane information.

The cluster will be ready in about 5-7min, and Rancher will be running on the hostname you provided in 10-15min. Congrats! You just deployed Rancher with a single button press and a single API/language.