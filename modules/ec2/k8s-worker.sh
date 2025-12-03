#!/bin/bash
set -e  # Exit on error
set -x  # Print commands as they execute

# Log everything to a file
exec > >(tee /var/log/k8s-worker-setup.log)
exec 2>&1

echo "Starting Kubernetes worker node setup..."

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

sudo systemctl status containerd

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


# Install crictl: CRI-O is an implementation of the Container Runtime Interface (CRI) used by the kubelet to interact with container runtimes.
export CRICTL_VERSION="v1.30.1"
export CRICTL_ARCH=$(dpkg --print-architecture)
wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$CRICTL_VERSION/crictl-$CRICTL_VERSION-linux-$CRICTL_ARCH.tar.gz
tar zxvf crictl-$CRICTL_VERSION-linux-$CRICTL_ARCH.tar.gz -C /usr/local/bin
rm -f crictl-$CRICTL_VERSION-linux-$CRICTL_ARCH.tar.gz
crictl version

# Set hostname for this worker node
sudo hostnamectl set-hostname k8s-worker-${worker_index}

echo "Kubernetes worker node setup complete!"
echo "Waiting for master node to be ready and fetching join command..."

# Master node private IP (passed from Terraform)
MASTER_IP="${master_ip}"

# Wait for master node to be ready and join command to be available
MAX_RETRIES=60  # Wait up to 10 minutes (60 * 10 seconds)
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Attempt $((RETRY_COUNT + 1))/$MAX_RETRIES: Trying to fetch join command from master..."
    
    # Try to fetch the join command from master via HTTP
    # Use || true to prevent script exit when curl fails (due to set -e)
    JOIN_CMD=$(curl -sf http://$MASTER_IP:8080/join-command.sh 2>/dev/null || true)
    
    if [ -n "$JOIN_CMD" ] && [ "$JOIN_CMD" != "Waiting for master setup to complete..." ]; then
        echo "Successfully fetched join command from master!"
        echo "Joining the cluster..."
        
        # Execute the join command
        sudo $JOIN_CMD
        
        if [ $? -eq 0 ]; then
            echo "Successfully joined the cluster!"
            exit 0
        else
            echo "Failed to execute join command, will retry..."
        fi
    else
        echo "Master not ready yet or join command not available..."
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 10
done

echo "ERROR: Failed to join cluster after $MAX_RETRIES attempts"
echo "Master node may not be ready. Check master node logs at /var/log/k8s-master-setup.log"
echo "You can manually join by running: sudo kubeadm join $MASTER_IP:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
exit 1