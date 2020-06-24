echo '192.168.1.4 master-node' | sudo tee -a /etc/hosts
sudo swapoff -a
sudo apt-get update -y
sudo apt-get install apt-transport-https ca-certificates curl software-properties-common -y
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
echo 'deb http://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo add-apt-repository 'deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable'
sudo apt-get update -y
sudo apt-get install docker-ce kubelet kubeadm kubectl -y

sudo kubeadm join master-node:6443 --token 'c4qu79.6obz85w0xa57ho99' --discovery-token-unsafe-skip-ca-verification