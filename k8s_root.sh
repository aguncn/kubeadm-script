#!/bin/bash
# Version V1.0 2019-05-18

if [ `whoami` != "root" ];then echo "[error] You need to switch to root user to execute this command" ; exit 1 ;fi

K8S_VERSION="1.14.1"
General_user="devops"

K8S_VER=1.14.1
dir_path=$(cd `dirname $0`;cd ../;pwd)
cmd_path=$dir_path/cmd
cert_path=$dir_path/cert
rpm_path=$dir_path/rpm

RED_COLOR='\E[1;31m'
GREEN_COLOR='\E[1;32m'
YELOW_COLOR='\E[1;33m'
BLUE_COLOR='\E[1;34m'
PINK='\E[1;35m'
RES='\E[0m'

function if_file_exist_del() {
  if [ -e $1 ]; then
    rm -f $1
  fi
}

env_setting(){
  echo -e "${PINK}***** $FUNCNAME *****${RES}"
  systemctl stop firewalld.service
  systemctl disable firewalld.service
  setenforce 0
  sed -i "s/^SELINUX=enforcing/SELINUX=disabled/g" /etc/sysconfig/selinux 
  sed -i "s/^SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config 
  sed -i "s/^SELINUX=permissive/SELINUX=disabled/g" /etc/sysconfig/selinux 
  sed -i "s/^SELINUX=permissive/SELINUX=disabled/g" /etc/selinux/config
  swapoff -a
  sed -i 's/.*swap.*/#&/' /etc/fstab
  
  iptables -P INPUT ACCEPT
  iptables -P FORWARD ACCEPT
  iptables -P OUTPUT ACCEPT
  iptables -t nat -P PREROUTING ACCEPT
  iptables -t nat -P POSTROUTING ACCEPT
  iptables -t nat -P OUTPUT ACCEPT
  iptables -t mangle -P PREROUTING ACCEPT
  iptables -t mangle -P OUTPUT ACCEPT
  iptables -F
  iptables -t nat -F
  iptables -t mangle -F
  iptables -X
  iptables -t nat -X
  iptables -t mangle -X
  
  k8s_kernel_conf=/etc/sysctl.d/k8s.conf
  if_file_exist_del $k8s_kernel_conf
  cat<<EOF >$k8s_kernel_conf
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
fs.may_detach_mounts = 1
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_watches=89100
fs.file-max=52706963
fs.nr_open=52706963
net.netfilter.nf_conntrack_max=2310720
vm.swappiness=0
EOF

  sysctl -p
  sysctl --system
  
  yum install bridge-utils ipset ipvsadm sysstat libseccomp conntrack  conntrack-tools socat -y


  modprobe br_netfilter
  modprobe -- ip_vs
  modprobe -- ipip
  modprobe -- tun
  modprobe -- ip_vs_rr
  modprobe -- ip_vs_wrr
  modprobe -- ip_vs_sh
  modprobe -- nf_conntrack_ipv4
  modprobe -- nf_conntrack_ipv6
  
  ipvs_no=$(cat /etc/rc.local|grep ip_vs|wc -l)
  if [ $ipvs_no -eq 0 ]; then
      echo "modprobe br_netfilter" >> /etc/rc.local
      echo "modprobe -- ip_vs" >> /etc/rc.local
      echo "modprobe -- ipip" >> /etc/rc.local
      echo "modprobe -- tun" >> /etc/rc.local
      echo "modprobe -- ip_vs_rr" >> /etc/rc.local
      echo "modprobe -- ip_vs_wrr" >> /etc/rc.local
      echo "modprobe -- ip_vs_sh" >> /etc/rc.local
      echo "modprobe -- nf_conntrack_ipv4" >> /etc/rc.local
      echo "modprobe -- nf_conntrack_ipv6" >> /etc/rc.local
  fi  
  k8s_sudoers_conf=/etc/sudoers.d/k8s_sudoers
  if_file_exist_del $k8s_sudoers_conf
   cat<<EOF >$k8s_sudoers_conf
devops ALL = (root) NOPASSWD:/bin/systemctl restart docker
devops ALL = (root) NOPASSWD:/bin/systemctl reload docker
devops ALL = (root) NOPASSWD:/bin/systemctl daemon-reload
devops ALL = (root) NOPASSWD:/bin/systemctl start kubelet
devops ALL = (root) NOPASSWD:/bin/systemctl stop docker
devops ALL = (root) NOPASSWD:/bin/systemctl start docker
devops ALL = (root) NOPASSWD:/bin/systemctl status docker
devops ALL = (root) NOPASSWD:/bin/systemctl stop kubelet
devops ALL = (root) NOPASSWD:/bin/systemctl restart kubelet
devops ALL = (root) NOPASSWD:/bin/systemctl status kubelet
devops ALL = (root) NOPASSWD:/usr/sbin/ipvsadm
devops ALL = (root) NOPASSWD:/usr/bin/docker
devops ALL = (root) NOPASSWD:/usr/local/bin/kubeadm
devops ALL = (root) NOPASSWD:/usr/local/bin/kubectl
devops ALL = (root) NOPASSWD:/usr/bin/chown -R devops /etc/kubernetes/
EOF
}


init_kube(){
  echo -e "${PINK}***** $FUNCNAME *****${RES}"
  #systemctl stop kubelet
  #systemctl stop docker

# add
  systemctl stop kubelet.service
  docker ps |grep -v "CONTAINER ID"|awk '{print $1}'|xargs -I {} docker stop {}
  docker ps -a|grep -v "CONTAINER ID"|awk '{print $1}'|xargs -I {} docker rm {}
  systemctl stop docker.service
  sleep 30
  for i in $(df|awk '$6 ~ /.*kubelet.*/{print $6}');do
    umount $i
  done

  rm -rf /etc/cni/
  rm -rf /opt/cni/bin/*
  ifconfig docker0 down
  ip link delete docker0
  rm -f /usr/local/bin/kube*
  rm -f /usr/bin/kube*
  
  pki_dir=/etc/kubernetes
  mkdir -p ${pki_dir}
  rm -rf ${pki_dir}/* 
  chown -R ${General_user}.${General_user} ${pki_dir}
  chmod -R 755 ${pki_dir}

  yum remove kubeadm -y
  yum remove kubectl -y
  yum remove kubelet -y
  yum localinstall $rpm_path/*.rpm -y  --skip-broken
  chown -R $(id -u ${General_user}):$(id -g ${General_user}) /etc/systemd/system/kubelet*
  # tar xf cni-plugins-amd64-v0.7.5.tgz -C /opt/cni/bin
  /bin/cp /usr/bin/kube* /usr/local/bin/
 
  ifconfig -a|grep  -vE '(^[[:space:]]|^$)'|grep -E '(veth|flannel|kube|cni|dummy)'|awk -F ":" '{print $1}'|awk '{for(i=1;i<=NF;i++){print "ip link set " $i " down";}}'|sh
  ifconfig -a|grep  -vE '(^[[:space:]]|^$)'|grep -E '(veth|flannel|kube|cni|dummy)'|awk -F ":" '{print $1}'|awk '{for(i=1;i<=NF;i++){print "ip link delete " $i;}}'|sh
  ip route|grep 10.244|awk '{print $1}'|awk '{for(i=1;i<=NF;i++){print "ip route delete " $i;}}'|sh

  modprobe -r ipip
  modprobe -r ip_gre
  modprobe  ipip
	
  kubelet_sysconfig=/etc/sysconfig/kubelet
  if_file_exist_del $kubelet_sysconfig
  cat<<EOF >$kubelet_sysconfig
KUBELET_EXTRA_ARGS="--pod-infra-container-image=harbor.xxx.com.cn/3rd_part/k8s.gcr.io/pause:3.1"
EOF

  systemctl daemon-reload
  systemctl start docker
  systemctl enable kubelet && systemctl restart kubelet

  echo -e "${GREEN_COLOR}***** k8s root init system success ******${RES}"
}

function main(){
  kubeadm reset -f
  ipvsadm -C
  env_setting
  init_kube
}
main
