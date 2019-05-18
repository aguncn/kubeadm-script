#!/bin/bash
# Version V1.0 2019-05-18

if [ `whoami` != "docker" ];then echo "[error] You need to switch to docker user to execute this command" ; exit 1 ;fi

K8S_VER=1.14.1
dir_path=$(cd `dirname $0`;cd ../;pwd)
cmd_path=$dir_path/cmd
cert_path=$dir_path/cert
rpm_path=$dir_path/rpm
software_path=$dir_path/software
yaml_path=$dir_path/yaml


THIS_HOST=$(hostname -i)
LOCAL_HOST=$(hostname)
LOCAL_HOST_L=${LOCAL_HOST,,}
pki_dir=/etc/kubernetes/pki
K8S_API_PORT=6443
General_user=devops
REGISTRY=harbor.xxx.com.cn/3rd_part/k8s.gcr.io
cs=$software_path/cfssl
csj=$software_path/cfssljson

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
controlPlaneEndpoint: ${THIS_HOST}:${K8S_API_PORT}
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

cert_init() {
  mkdir  -p  k8s_cert_tmp
  cp $cert_path/* ./k8s_cert_tmp
  chmod +x $cs
  chmod +x $csj
  cd k8s_cert_tmp
  sed -i "s/LOCAL_HOST_L/${LOCAL_HOST_L}/g;s/THIS_HOST/${THIS_HOST}/g" etcd-server.json
  sed -i "s/LOCAL_HOST_L/${LOCAL_HOST_L}/g;s/THIS_HOST/${THIS_HOST}/g" etcd-peer.json
  sed -i "s/LOCAL_HOST_L/${LOCAL_HOST_L}/g;s/THIS_HOST/${THIS_HOST}/g" apiserver.json
	
  $cs gencert -ca=ca.crt -ca-key=ca.key -config=ca-config.json -profile=server etcd-server.json|$csj -bare server
  $cs gencert -ca=ca.crt -ca-key=ca.key -config=ca-config.json -profile=client etcd-client.json|$csj -bare client
  $cs gencert -ca=ca.crt -ca-key=ca.key -config=ca-config.json -profile=peer etcd-peer.json|$csj -bare peer
  $cs gencert -ca=front-proxy-ca.crt -ca-key=front-proxy-ca.key -config=ca-config.json -profile=client front-proxy-client.json|$csj -bare front-proxy-client
  $cs gencert -ca=ca.crt -ca-key=ca.key -config=ca-config.json -profile=server apiserver.json|$csj -bare apiserver
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

function main(){
  cert_init
  kubeadmConf
  master_install
}

main
