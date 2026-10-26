# ☸️ Two-Node Kubeadm Kubernetes Cluster Setup on AWS EC2

This guide walks through creating a two-node **Kubernetes v1.36.x** cluster using **kubeadm**, **containerd** runtime, and **Flannel CNI** on AWS EC2 instances running Ubuntu 24.04 LTS.

---

## 1. Infrastructure Overview

| Node | Role | Instance Type | vCPU / RAM | Hostname | Private IP (Example) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **k8s-master** | Control Plane | `t3.medium` | 2 vCPU / 4 GB | `k8s-master` | `172.31.36.42` |
| **k8s-worker** | Worker / Slave | `t3.large` | 2 vCPU / 8 GB | `k8s-worker` | `172.31.30.214` |

Both instances run **Ubuntu 24.04 LTS** with a **30 GB** root volume in the same VPC and Subnet / Security Group.

> **Sizing Note**:  
> The control plane carries a taint by default, so application pods land on the worker node. Their combined CPU requests require sufficient headroom. Use `t3.large` (or `t3.xlarge`) for the worker node to ensure smooth scheduling and operation.

---

## 2. Security Group Configuration

AWS security groups are stateful, so only **inbound rules** are required. Leave outbound rules set to allow all traffic (`0.0.0.0/0`) so nodes can pull images from registries (`registry.k8s.io`, AWS ECR, Docker Hub).

### Approach A: Self-Referencing Rule (Recommended & Cleanest)
Attach one security group to **both** instances with a **self-referencing rule**:
- **Type**: All traffic
- **Source**: The security group's own ID (`sg-xxxxxxxxx`)

This covers all intra-cluster pod and node networking in a single rule. Then add:
1. **SSH (TCP 22)**: Source = Your IP (`/32`)
2. **NodePort Range (TCP 30000-32767)**: Source = Your IP (`/32`) or `0.0.0.0/0` (for web access)

---

### Approach B: Explicit Port List

#### Control Plane (Master Node) Inbound Rules:

| Protocol | Port Range | Purpose | Source |
| :--- | :--- | :--- | :--- |
| TCP | `6443` | Kubernetes API server | Worker node IP + Your Admin IP |
| TCP | `2379-2380` | etcd client and peer | Master itself |
| TCP | `10250` | kubelet API | Master + Worker |
| TCP | `10257` | kube-controller-manager | Master itself |
| TCP | `10259` | kube-scheduler | Master itself |
| TCP | `10256` | kube-proxy health check | Master + Worker |
| UDP | `8472` | Flannel VXLAN overlay network | Master + Worker |
| TCP | `22` | SSH | Your IP `/32` |

#### Worker (Slave Node) Inbound Rules:

| Protocol | Port Range | Purpose | Source |
| :--- | :--- | :--- | :--- |
| TCP | `10250` | kubelet API | Master node IP |
| TCP | `10256` | kube-proxy health check | Master + Worker |
| TCP | `30000-32767` | NodePort Services (Web UI) | Your IP `/32` or `0.0.0.0/0` |
| UDP | `8472` | Flannel VXLAN overlay network | Master + Worker |
| TCP | `22` | SSH | Your IP `/32` |

> ⚠️ **Critical Troubleshooting Ports:**
> - **Worker TCP 10250**: Without this, the cluster looks healthy, but `kubectl logs` and `kubectl exec` will hang or time out.
> - **UDP 8472**: Without this, Flannel overlay networking fails; pods come up as `Running` but cannot communicate with each other across nodes.

---

## 3. Node Preparation (Run on BOTH Nodes)

Perform these steps on **both** the Master and Worker node.

### Step 3.1: Set Hostname
The `preserve_hostname: true` directive prevents cloud-init from resetting hostnames on reboot.

**On Master Node:**
```bash
sudo hostnamectl set-hostname k8s-master
echo "preserve_hostname: true" | sudo tee -a /etc/cloud/cloud.cfg
exec bash
```

**On Worker / Slave Node:**
```bash
sudo hostnamectl set-hostname k8s-worker
echo "preserve_hostname: true" | sudo tee -a /etc/cloud/cloud.cfg
exec bash
```

---

### Step 3.2: Disable Swap
The kubelet service will fail to start if swap is enabled.
```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

---

### Step 3.3: Kernel Modules & Sysctl Settings
Load required kernel modules for container networking:
```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
```

---

### Step 3.4: Install & Configure containerd
Install `containerd` and enable `SystemdCgroup = true` (critical for systemd cgroup management):
```bash
sudo apt-get update
sudo apt-get install -y containerd apt-transport-https ca-certificates curl gpg

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd
```

---

### Step 3.5: Install Kubernetes Packages (v1.36)
Add Kubernetes apt repository and install `kubelet`, `kubeadm`, and `kubectl`:
```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

---

### Step 3.6: Verification Checklist Before Proceeding
Run on **both** nodes to verify settings:
```bash
swapon --show                                  # Must return EMPTY
grep SystemdCgroup /etc/containerd/config.toml # Must return: SystemdCgroup = true
sysctl net.ipv4.ip_forward                     # Must return: net.ipv4.ip_forward = 1
kubeadm version                                # Must print: v1.36.x
hostnamectl --static                           # Must match: k8s-master or k8s-worker
```

---

## 4. Initialise the Control Plane (Run on MASTER Node Only)

Advertise the instance's **private IP** (AWS EC2 instances do not manage their public/elastic IP on the interface).

```bash
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=$(hostname -I | awk '{print $1}')
```

> **Note on CIDR**: Flannel's default pod CIDR `10.244.0.0/16` does not collide with the default AWS VPC CIDR `172.31.0.0/16`.

### Configure kubectl for Regular User:
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### Install Flannel CNI:
```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

> 💾 **Important**: Copy and save the `kubeadm join` command printed at the end of `kubeadm init`.  
> *(If lost, regenerate it anytime with: `kubeadm token create --print-join-command`)*.

### Confirm Control Plane Status:
```bash
kubectl get nodes
kubectl get pods -n kube-system
kubectl get pods -n kube-flannel
```
*(The master node will transition from `NotReady` to `Ready` once Flannel and CoreDNS pods reach `Running` status).*

---

## 5. Join the Worker Node (Run on WORKER Node Only)

Execute the `kubeadm join` command (as root or with `sudo`) on the **Worker Node**:

```bash
sudo kubeadm join <MASTER_PRIVATE_IP>:6443 \
  --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

*(Tokens expire after 24 hours. You can clean up old tokens on the master with `kubeadm token delete <token>`)*.

---

## 6. Cluster Verification (From MASTER Node)

Wait 30-60 seconds for Flannel's DaemonSet to schedule onto the worker node and verify:

```bash
kubectl get nodes -o wide
```
Output should show:
```text
NAME         STATUS   ROLES           AGE     VERSION   INTERNAL-IP     OS-IMAGE             KERNEL-VERSION
k8s-master   Ready    control-plane   5m      v1.36.x   172.31.36.42    Ubuntu 24.04.x LTS   ...
k8s-worker   Ready    <none>          2m      v1.36.x   172.31.30.214   Ubuntu 24.04.x LTS   ...
```

Verify CNI daemon pods:
```bash
kubectl get pods -n kube-flannel -o wide
```

---

## 🚀 Next Step: Deploy Applications

Now that your two-node cluster is operational:
1. Follow the **[AWS_ECR_KUBEADM_DEPLOYMENT.md](AWS_ECR_KUBEADM_DEPLOYMENT.md)** guide to build & push images to AWS ECR and deploy the **Polyglot Retail Store** microservices app with one command.
