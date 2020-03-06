#!/bin/sh
# ref:https://www.cnblogs.com/huhyoung/p/9657186.html

master=192.168.1.162
node1=192.168.1.237
node2=192.168.1.189
kube_version=1.13.12
pause_version=3.1
etcd_version=3.2.24
coredns_version=1.2.6

add_k8s_repo_remote() {
	local host=$1
	ssh root@${host} "[ -f /etc/yum.repos.d/kubernetes.repo ]" && return

	ssh root@${host} "cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-aarch64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg
    https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF"
	ssh root@${host} "yum repolist"
	ssh root@${host} "[ -f yum-key.gpg ] || { wget https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg && rpm --import yum-key.gpg }"
	ssh root@${host} "[ -f rpm-package-key.gpg ] || { wget https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg && rpm --import rpm-package-key.gpg }"
}

install_dependencies() {
	local host=$1
	ssh root@${host} "yum install -y -q wget"
	ssh root@${host} "yum install -y -q docker"
	ssh root@${host} "yum install -y -q kubeadm-1.13.4"
	ssh root@${host} "yum install -y -q kubelet-1.13.4"
	ssh root@${host} "yum install -y -q kubectl-1.13.4"
	ssh root@${host} "yum install -y -q kubernetes-cni-0.6.0"
	ssh root@${host} "yum install -y -q cri-tools-1.12.0"
	#ssh root@${host} "yum downgrade -y kubelet-1.13.4 kubectl-1.13.4 kubeadm-1.13.4 cri-tools-1.12.0 kubernetes-cni-0.6.0"
}

configure_hosts() {
	local host=$1
	ssh root@${host} "grep -q master /etc/hosts" && return
	ssh root@${host} "cat << EOF >> /etc/hosts

${master} master
${node1} node1
${node2} node2
EOF"
}

deploy_host() {
	local host=$1
	add_k8s_repo_remote ${host}
	ssh root@${host} "setenforce 0"
	ssh root@${host} "systemctl stop firewalld"
	ssh root@${host} "systemctl disable firewalld"
	ssh root@${host} "sysctl -w net.bridge.bridge-nf-call-iptables=1"
	ssh root@${host} "[ -f /etc/sysctl.d/k8s.conf ] || echo 'net.bridge.bridge-nf-call-iptables=1' > /etc/sysctl.d/k8s.conf"
	ssh root@${host} "swapoff -a && sed -i '/swap/ s/^/#/' /etc/fstab"
	install_dependencies ${host}
	ssh root@${host} "systemctl start docker"
	ssh root@${host} "systemctl enable docker"
	ssh root@${host} "systemctl enable kubelet"
	configure_hosts ${host}
}

deploy_master() {
	ssh root@${master} "kubeadm config images list"

	ssh root@${master} "docker pull docker.io/mirrorgooglecontainers/kube-apiserver-arm64:v${kube_version}"
	ssh root@${master} "docker pull docker.io/mirrorgooglecontainers/kube-controller-manager-arm64:v${kube_version}"
	ssh root@${master} "docker pull docker.io/mirrorgooglecontainers/kube-scheduler-arm64:v${kube_version}"
	ssh root@${master} "docker pull docker.io/mirrorgooglecontainers/kube-proxy-arm64:v${kube_version}"
	ssh root@${master} "docker pull docker.io/mirrorgooglecontainers/pause-arm64:${pause_version}"
	ssh root@${master} "docker pull docker.io/mirrorgooglecontainers/etcd-arm64:${etcd_version}"
	ssh root@${master} "docker pull docker.io/coredns/coredns:${coredns_version}"

	ssh root@${master} "docker tag docker.io/mirrorgooglecontainers/kube-apiserver-arm64:v${kube_version} k8s.gcr.io/kube-apiserver:v${kube_version}" 
	ssh root@${master} "docker tag docker.io/mirrorgooglecontainers/kube-controller-manager-arm64:v${kube_version} k8s.gcr.io/kube-controller-manager:v${kube_version}" 
	ssh root@${master} "docker tag docker.io/mirrorgooglecontainers/kube-scheduler-arm64:v${kube_version} k8s.gcr.io/kube-scheduler:v${kube_version}"
	ssh root@${master} "docker tag docker.io/mirrorgooglecontainers/kube-proxy-arm64:v${kube_version} k8s.gcr.io/kube-proxy:v${kube_version}"
	ssh root@${master} "docker tag docker.io/mirrorgooglecontainers/pause-arm64:${pause_version} k8s.gcr.io/pause:${pause_version}"
	ssh root@${master} "docker tag docker.io/mirrorgooglecontainers/etcd-arm64:${etcd_version} k8s.gcr.io/etcd:${etcd_version}"
	ssh root@${master} "docker tag docker.io/coredns/coredns:${coredns_version} k8s.gcr.io/coredns:${coredns_version}"

	ssh root@${master} "docker rmi docker.io/mirrorgooglecontainers/kube-apiserver-arm64:v${kube_version}"
	ssh root@${master} "docker rmi docker.io/mirrorgooglecontainers/kube-controller-manager-arm64:v${kube_version}"
	ssh root@${master} "docker rmi docker.io/mirrorgooglecontainers/kube-scheduler-arm64:v${kube_version}"
	ssh root@${master} "docker rmi docker.io/mirrorgooglecontainers/kube-proxy-arm64:v${kube_version}"
	ssh root@${master} "docker rmi docker.io/mirrorgooglecontainers/pause-arm64:${pause_version}"
	ssh root@${master} "docker rmi docker.io/mirrorgooglecontainers/etcd-arm64:${etcd_version}"
	ssh root@${master} "docker rmi docker.io/coredns/coredns:${coredns_version}"
}

init_master() {
	ssh root@${master} "kubeadm init --pod-network-cidr=10.244.0.0/16"
	ssh root@${master} "grep KUBECONFIG /etc/profile || { echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' >> /etc/profile }"
	#ssh root@${master} "kubeadm reset"
}

install_flannel() {
	ssh root@${master} "kubectl apply -f  https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
}

check_k8s() {
	ssh root@${master} kubectl get node
	ssh root@${master} kubectl get po --namespace kube-system -o wide
}

create_docker_demo() {
	ssh root@${master} "[ -d ~/docker-test ]" && return

	cat << EOF > app.js
const http = require('http');
const os = require('os');

console.log("Node Server starting...");

var handler = function(request, response) {
        console.log("Received request from " + request.connection.remoteAddress);
        response.writeHead(200);
        response.end("You've hit " + os.hostname() + "\n");
};

var www = http.createServer(handler);
www.listen(8080);

EOF
	cat << EOF > Dockerfile
FROM node
ADD app.js /app.js
ENTRYPOINT ["node","app.js"]
EOF
	ssh root@${master} "mkdir -p ~/docker-test"
	scp app.js Dockerfile root@${master}/root/docker-test/
	ssh root@${master} "cd ~/docker-test && docker build -t mynode . && docker run --name mynode-container -p 8080:8080 -d mynode"

	ssh root@${master} "docker tag mynode chenzhihui244/mynode"
	ssh root@${master} "docker login && docker push chenzhihui244/mynode"
}

deploy_service() {
	ssh root@${master} "kubectl run mynode --image=chenzhihui244/mynode --port=8080 --generator=run/v1"
	ssh root@${master} "kubectl expose rc mynode --type=LoadBalancer --name mynode-http"
	ssh root@${master} "kubectl get svc"
	ssh root@${master} "kubectl scale rc mynode --replicas=3"
	ssh root@${master} "kubectl get pods -o wide"
	ssh root@${master} "kubectl get rc"
	ssh root@${master} "curl 10.105.110.140:8080"
}

deploy_host ${node1}
#deploy_host ${node2}

#deploy_host ${master}
#deploy_master
#init_master
#install_flannel
