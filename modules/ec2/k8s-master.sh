#!/bin/bash
set -e  # Exit on error
set -x  # Print commands as they execute

# Log everything to a file
exec > >(tee /var/log/k8s-master-setup.log)
exec 2>&1

# For Ubuntu DISTRIB_RELEASE=22

# Update the system
sudo apt-get update
sudo apt-get upgrade -y

# Install Containerd as container runtime
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install containerd.io -y
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sed -e 's/SystemdCgroup = false/SystemdCgroup = true/g' -i /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd
cat <<EOF | tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

# Disable swap
# Predictable performance: Swap can lead to unpredictable node performance.
# Resource management: Kubernetes manages container resources, and swap can interfere with this.
# Consistency: Ensures consistent behavior across all nodes in the cluster.
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab


# Add some settings to sysctl
# These settings are crucial for Kubernetes networking to function correctly.
# They allow Kubernetes services to communicate with each other and the outside world.
# They ensure that iptables rules are properly applied to bridge traffic.
sudo tee /etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF


# Enable kernel modules
# overlay: Needed for efficient container filesystem operations.
# br_netfilter: Enables transparent masquerading and facilitates Virtual Extensible LAN (VxLAN) traffic for communication between Kubernetes pods across nodes.
sudo modprobe overlay
sudo modprobe br_netfilter

# Reload sysctl
sudo sysctl --system

systemctl status containerd

# Add Kubernetes repo
sudo apt-get install -y apt-transport-https ca-certificates curl
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

# Install Kubernetes components
sudo apt-get update
sudo apt-get install -y kubelet=1.30.3-1.1 kubeadm=1.30.3-1.1 kubectl=1.30.3-1.1
sudo apt-mark hold kubelet kubeadm kubectl
# apt-mark hold command marks the kubelet, kubeadm, and kubectl packages as "held back".
# When you run apt-get upgrade, these packages will not be upgraded, even if newer versions are available.


# Install critctl: CRI-O is an implementation of the Container Runtime Interface (CRI) used by the kubelet to interact with container runtimes.
export CRICTL_VERSION="v1.30.1"
export CRICTL_ARCH=$(dpkg --print-architecture)
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRICTL_VERSION/crictl-$CRICTL_VERSION-linux-$CRICTL_ARCH.tar.gz
tar zxvf crictl-$CRICTL_VERSION-linux-$CRICTL_ARCH.tar.gz -C /usr/local/bin
rm -f crictl-$CRICTL_VERSION-linux-$CRICTL_ARCH.tar.gz
crictl version

# Get the master node's IP address
MASTER_IP=$(hostname -I | awk '{print $1}')

# Initialize the cluster
# Initialize the Kubernetes cluster
# --pod-network-cidr=192.168.0.0/16 prevents conflict with VPC subnet (10.0.1.0/24)
# --node-name=k8s-master-1 sets a friendly hostname instead of AWS private DNS
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --node-name=k8s-master-1 --kubernetes-version 1.30.3

# Breakdown the above command:

# kubeadm init: This is the primary command used to initialize a Kubernetes control-plane node.
# It bootstraps the Kubernetes control plane, which includes components like the API server, controller manager, and scheduler.

# --pod-network-cidr=192.168.0.0/16: It specifies the subnet range to be used for pod IP addresses.
# 192.168.0.0/16 is the CIDR (Classless Inter-Domain Routing) notation representing this subnet.
# This CIDR range is used to assign IP addresses to pods across the cluster.
# It helps in setting up the overlay network that allows pods to communicate across different nodes.
# The chosen CIDR should not overlap with your node network or any other network in your infrastructure.

# Set up kubectl for the ubuntu user (not root)
mkdir -p /home/ubuntu/.kube
sudo cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
sudo chown ubuntu:ubuntu /home/ubuntu/.kube/config

# Also set up for root user
mkdir -p /root/.kube
sudo cp -i /etc/kubernetes/admin.conf /root/.kube/config

# Install Calico CNI plugin
# Calico is simpler and doesn't conflict with VPC subnet routing
echo "Installing Calico CNI plugin..."
export KUBECONFIG=/etc/kubernetes/admin.conf

# Download and apply Calico manifest
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# Wait for Calico to be ready
echo "Waiting for Calico pods to be ready..."
sleep 10  # Give pods time to be created

# Wait for Calico pods (don't exit if this fails, pods might still be starting)
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=300s || true
kubectl wait --for=condition=ready pod -l k8s-app=calico-kube-controllers -n kube-system --timeout=300s || true

echo "Calico CNI plugin installed successfully!"

echo "Kubernetes master node setup complete!"

# Generate and save the join command for worker nodes
echo "Generating join command for worker nodes..."
kubeadm token create --print-join-command > /tmp/join-command.sh
chmod 644 /tmp/join-command.sh

# Print the join command for reference
echo "Run the following command on your worker nodes to join the cluster:"
cat /tmp/join-command.sh

# Start a simple HTTP server to serve the join command to worker nodes
# This allows workers to fetch the join command automatically
echo "Starting HTTP server on port 8080 to serve join command..."
cd /tmp
nohup python3 -m http.server 8080 --bind 0.0.0.0 > /var/log/join-server.log 2>&1 &
echo "HTTP server started. Workers can fetch join command from http://<master-ip>:8080/join-command.sh"

# kubeadm token create: This part of the command creates a new bootstrap token.
# Bootstrap tokens are used for establishing bidirectional trust between a node wanting to join the cluster and the control plane node.
# --print-join-command: This flag tells kubeadm to print out the full kubeadm join command that can be used to join a new node to the cluster

sudo hostnamectl set-hostname k8s-master
