#!/bin/bash
# Version V0.09 2019-05-18

if [ `whoami` != "docker" ];then echo "[error] You need to switch to docker user to execute this command" ; exit 1 ;fi

Domain_name=$1
Node_type=$2

K8S_VER=1.14.1
dir_path=$(cd `dirname $0`;pwd)
cmd_path=$dir_path/cmd
cert_path=$dir_path/cert
rpm_path=$dir_path/rpm
software_path=$dir_path/software
yaml_path=$dir_path/yaml


# 每一个新集群，此处必须修改
HOST_1=1.1.1.1
HOST_2=1.1.1.2
HOST_3=1.1.1.3

Domain_name=$1
Node_type=$2
# 定义常量
THIS_HOST=$(hostname -i)
LOCAL_HOST=$(hostname)
LOCAL_HOST_L=${LOCAL_HOST,,}
pki_dir=/etc/kubernetes/pki
K8S_API_PORT=6443
General_user=devpos
REGISTRY=harbor.xxx.com.cn/3rd_part/k8s.gcr.io
ETCD_VERSION=3.3.10
ETCD_CLI_PORT=2379
ETCD_CLU_PORT=2380
TOKEN=xxx-k8s-etcd-token
CLUSTER_STATE=new
CLUSTER=${HOST_1}=http://${HOST_1}:${ETCD_CLU_PORT},${HOST_2}=http://${HOST_2}:${ETCD_CLU_PORT},${HOST_3}=http://${HOST_3}:${ETCD_CLU_PORT}
etcd_data_dir=$HOME/etcd/etcd-data
cs=$software_path/cfssl
csj=$software_path/cfssljson

#判断本机IP是否在集群内
function ip_in_cluster() {
	if [[ ${THIS_HOST} != ${HOST_1} && ${THIS_HOST} != ${HOST_2} && ${THIS_HOST} != ${HOST_3} ]]; then
	  echo "Ip not in the k8s cluster host. please modify the HOST_1, HOST_2, HOST_3 at k8s_ha_master.sh file."
	  exit 110
	fi
}

function if_file_exist_del() {
  if [ -e $1 ]; then
    rm -f $1
  fi
}


function kubeadmConf() {
  kubeadm_conf=kubeadm-config.yaml
  if_file_exist_del $kubeadm_conf
  cat << EOF >$kubeadm_conf
apiVersion: kubeadm.k8s.io/v1beta1
kind: ClusterConfiguration
imageRepository: ${REGISTRY}
kubernetesVersion: ${K8S_VER}
controlPlaneEndpoint: ${Domain_name}:${K8S_API_PORT}
etcd:
  external:
    endpoints:
    - https://${HOST_1}:${ETCD_CLI_PORT}
    - https://${HOST_2}:${ETCD_CLI_PORT}
    - https://${HOST_3}:${ETCD_CLI_PORT}
    caFile: ${pki_dir}/etcd/ca.crt
    certFile: ${pki_dir}/apiserver-etcd-client.crt
    keyFile: ${pki_dir}/apiserver-etcd-client.key
apiServer:
  extraArgs:
    service-node-port-range: 30000-50000
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: "ipvs"
EOF
}

cert_ha_init() {
  mkdir  -p  k8s_cert_tmp
  cp $cert_path/* ./k8s_cert_tmp
  chmod +x $cs
  chmod +x $csj
  cd k8s_cert_tmp
  sed -i "s/LOCAL_HOST_L/${LOCAL_HOST_L}/g;s/HOST_1/${HOST_1}/g;s/HOST_2/${HOST_2}/g;s/HOST_3/${HOST_3}/g;s/Domain_name/${Domain_name}/g" ha-etcd-server.json
  sed -i "s/LOCAL_HOST_L/${LOCAL_HOST_L}/g;s/HOST_1/${HOST_1}/g;s/HOST_2/${HOST_2}/g;s/HOST_3/${HOST_3}/g;s/Domain_name/${Domain_name}/g" ha-etcd-peer.json
  sed -i "s/LOCAL_HOST_L/${LOCAL_HOST_L}/g;s/HOST_1/${HOST_1}/g;s/HOST_2/${HOST_2}/g;s/HOST_3/${HOST_3}/g;s/Domain_name/${Domain_name}/g" ha-apiserver.json
	
  $cs gencert -ca=ca.crt -ca-key=ca.key -config=ca-config.json -profile=server ha-etcd-server.json|$csj -bare server
  $cs gencert -ca=ca.crt -ca-key=ca.key -config=ca-config.json -profile=client etcd-client.json|$csj -bare client
  $cs gencert -ca=ca.crt -ca-key=ca.key -config=ca-config.json -profile=peer ha-etcd-peer.json|$csj -bare peer
  $cs gencert -ca=front-proxy-ca.crt -ca-key=front-proxy-ca.key -config=ca-config.json -profile=client front-proxy-client.json|$csj -bare front-proxy-client
  $cs gencert -ca=ca.crt -ca-key=ca.key -config=ca-config.json -profile=server ha-apiserver.json|$csj -bare apiserver
  $cs gencert -ca=ca.crt -ca-key=ca.key -config=ca-config.json -profile=client apiserver-kubelet-client.json|$csj -bare apiserver-kubelet-client

  mkdir -p $pki_dir/etcd
	
  cp server.pem $pki_dir/etcd/server.crt&&cp server-key.pem $pki_dir/etcd/server.key
  cp client.pem $pki_dir/etcd/healthcheck-client.crt&&cp client-key.pem $pki_dir/etcd/healthcheck-client.key
  cp client.pem $pki_dir/apiserver-etcd-client.crt&&cp client-key.pem $pki_dir/apiserver-etcd-client.key
  cp peer.pem $pki_dir/etcd/peer.crt&&cp peer-key.pem $pki_dir/etcd/peer.key
  cp ca.crt $pki_dir/etcd/ca.crt&&cp ca.key $pki_dir/etcd/ca.key
  
  cp front-proxy-ca.crt $pki_dir/front-proxy-ca.crt&&cp front-proxy-ca.key $pki_dir/front-proxy-ca.key
  cp front-proxy-client.pem $pki_dir/front-proxy-client.crt&&cp front-proxy-client-key.pem $pki_dir/front-proxy-client.key
  
  cp ca.crt $pki_dir/ca.crt&&cp ca.key $pki_dir/ca.key
  cp apiserver.pem $pki_dir/apiserver.crt&cp apiserver-key.pem $pki_dir/apiserver.key
  cp apiserver-kubelet-client.pem $pki_dir/apiserver-kubelet-client.crt&&cp apiserver-kubelet-client-key.pem $pki_dir/apiserver-kubelet-client.key
  
  cp sa.pub $pki_dir/sa.pub&&cp sa.key $pki_dir/sa.key
  cd ../
  rm -rf k8s_cert_tmp
}

function etcd_install() {
		# 如果有以前数据，先清除
		set +e
		sudo docker stop etcd &&sudo  docker rm etcd
		rm -rf ${etcd_data_dir}/*
		sudo systemctl restart docker
		set -e
		
		# 运行docker
		docker run \
		   -d \
		   -p ${ETCD_CLI_PORT}:${ETCD_CLI_PORT} \
		   -p ${ETCD_CLU_PORT}:${ETCD_CLU_PORT} \
		   --volume=${etcd_data_dir}:${etcd_data_dir} \
		   --volume=${pki_dir}:${pki_dir} \
		   --name etcd ${REGISTRY}/etcd:${ETCD_VERSION} \
		   /usr/local/bin/etcd \
		   --data-dir=${etcd_data_dir} --name ${THIS_HOST} \
		   --initial-advertise-peer-urls http://${THIS_HOST}:${ETCD_CLU_PORT} \
		   --listen-peer-urls http://0.0.0.0:${ETCD_CLU_PORT} \
		   --advertise-client-urls https://${THIS_HOST}:${ETCD_CLI_PORT} \
		   --listen-client-urls https://0.0.0.0:${ETCD_CLI_PORT} \
		   --initial-cluster ${CLUSTER} \
		   --initial-cluster-state ${CLUSTER_STATE} \
		   --initial-cluster-token ${TOKEN} \
		   --cert-file=${pki_dir}/etcd/server.crt \
		   --key-file=${pki_dir}/etcd/server.key \
		   --trusted-ca-file=${pki_dir}/etcd/ca.crt
		   
    echo "================================="
		echo "etcd start success"
}

function etcd_reset() {
	set +e
	docker stop etcd
	rm -rf ${etcd_data_dir}/*
	docker rm etcd
	set -e

}

function master_install(){
  sudo /usr/local/bin/kubeadm  init --config $kubeadm_conf
  sudo chown -R devops /etc/kubernetes/
  mkdir -p $HOME/.kube
  \cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
  chown $(id -u):$(id -g) $HOME/.kube/config
  General_user_HOME=`cat /etc/passwd |grep  -e ^${General_user} |awk -F: '{print $6}'`
  mkdir -p ${General_user_HOME}/.kube
  \cp -f /etc/kubernetes/admin.conf ${General_user_HOME}/.kube/config
  chown -R $(id -u ${General_user}):$(id -g ${General_user}) ${General_user_HOME}/.kube

  kubectl apply -f $yaml_path/secret
  kubectl apply -f $yaml_path/auto_cert_server
  kubectl apply -f $yaml_path/flannel
}

case ${Node_type} in
  "etcd")
    ip_in_cluster
    cert_ha_init
    etcd_install
    ;;
  "cert")
    cert_ha_init
    ;;
  "etcd_install")
    etcd_install
  ;;
  "master")	
    ip_in_cluster
    kubeadmConf
    master_install
  ;;
  *)
  echo "usage `basename $0` [Domain] [etcd|master]"
  ;;
esac
