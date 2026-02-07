# K3s Raspberry Pi Ansible Automation

Automated setup for a 4-node K3s cluster on Raspberry Pi devices using Ansible.

## 📋 Prerequisites

- 4 Raspberry Pi devices running Ubuntu Server
- Ansible installed on your local machine (`pip install ansible`)
- SSH access to all Pis (set up SSH keys or use initial password)
- All Pis on the same network

## 🚀 Quick Start

### 1. Setup SSH Keys (Recommended First)

Generate an SSH key if you don't have one:
```bash
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

Deploy SSH keys to all Pis:
```bash
ansible-playbook setup-ssh-keys.yml
```

After SSH keys are deployed, remove passwords from `inventory.ini`:
```bash
# Comment out or remove these lines from inventory.ini after SSH key setup
# ansible_password=YOUR_PASSWORD_HERE
# ansible_become_password=YOUR_PASSWORD_HERE
```

### 2. Install K3s Cluster

Run the main playbook to configure all nodes:
```bash
ansible-playbook site.yml
```

This will:
- ✅ Set hostnames to match inventory
- ✅ Disable WiFi and configure ethernet
- ✅ Enable memory cgroups (critical for containers)
- ✅ Upgrade all packages
- ✅ Install K3s server on control plane
- ✅ Join worker nodes to cluster
- ✅ Copy kubeconfig to `~/.kube/k3s-config`
- ✅ Taint control plane (no workloads scheduled there)

### 3. Install MetalLB Load Balancer

**Important**: Update the IP range in `metalb.yml` first!

Edit `metalb.yml` and set your IP pool:
```yaml
vars:
  metallb_ip_range: "192.168.68.200-192.168.68.220"  # Adjust to your network
```

Then run:
```bash
ansible-playbook metalb.yml
```

### 4. Configure kubectl

```bash
export KUBECONFIG=~/.kube/k3s-config
kubectl get nodes
```

To make it permanent:
```bash
echo 'export KUBECONFIG=~/.kube/k3s-config' >> ~/.bashrc
source ~/.bashrc
```

## 📂 Inventory Structure

```ini
[k3s_server]
k3s-cp-01 ansible_host=192.168.68.80

[k3s_agents]
k3s-node-01 ansible_host=192.168.68.84
k3s-node-02 ansible_host=192.168.68.87
k3s-node-03 ansible_host=192.168.68.89
```

## 🔒 Security Best Practices

### Option 1: Use SSH Keys (Recommended)
1. Run `setup-ssh-keys.yml` 
2. Remove password lines from `inventory.ini`

### Option 2: Use Ansible Vault for Passwords

Encrypt your inventory file:
```bash
ansible-vault encrypt inventory.ini
```

Or create a separate encrypted vars file:
```bash
# Create vars file
cat > secrets.yml <<EOF
ansible_user: ubuntu
ansible_password: YOUR_PASSWORD_HERE
ansible_become_password: YOUR_PASSWORD_HERE
EOF

# Encrypt it
ansible-vault encrypt secrets.yml

# Update inventory.ini to use the vars file
echo '@secrets.yml' >> inventory.ini
```

Run playbooks with vault password:
```bash
ansible-playbook site.yml --ask-vault-pass
```

Or use a password file:
```bash
echo "your-vault-password" > .vault_pass
ansible-playbook site.yml --vault-password-file .vault_pass
# Add .vault_pass to .gitignore!
```

## 📚 Playbook Details

### site.yml
Main playbook that:
- Configures baseline settings (hostname, network, updates)
- Enables memory cgroups for K3s
- Installs K3s server and agents
- Fetches kubeconfig for local use
- Taints control plane node

### metalb.yml
Installs MetalLB load balancer:
- Deploys MetalLB v0.14.3
- Configures IP address pool
- Sets up L2 advertisement

### setup-ssh-keys.yml
Configures SSH key authentication:
- Copies your public key to all Pis
- Optionally disables password auth

## 🎯 Common Tasks

### Test connectivity
```bash
ansible all -m ping
```

### Check cluster status
```bash
kubectl get nodes -o wide
kubectl get pods -A
```

### Restart a node
```bash
ansible k3s-node-01 -m reboot -b
```

### Update k3s
```bash
ansible k3s_server -m shell -a "/usr/local/bin/k3s-killall.sh" -b
ansible k3s_agents -m shell -a "/usr/local/bin/k3s-killall.sh" -b
ansible-playbook site.yml --tags k3s
```

### Deploy a test application
```bash
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=LoadBalancer
kubectl get svc nginx  # Check the EXTERNAL-IP from MetalLB
```

## 🔧 Customization

### Variables in site.yml

```yaml
# Baseline config
keep_eth0_dhcp: true

# K3s server flags
k3s_install_flags: "--write-kubeconfig-mode 644 --disable servicelb"

# Taint control plane
taint_control_plane: true
```

### Variables in metalb.yml

```yaml
metallb_ip_range: "192.168.68.200-192.168.68.220"
metallb_version: "v0.14.3"
```

## 📝 Next Steps

After cluster is running:
1. **Storage**: Install Longhorn for distributed storage
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml
   ```

2. **Ingress**: Install NGINX Ingress Controller
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
   ```

3. **Monitoring**: Install Prometheus/Grafana
   ```bash
   kubectl create namespace monitoring
   kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/kube-prometheus/main/manifests/setup/ -n monitoring
   ```

4. **Cert Manager**: For automated TLS certificates
   ```bash
   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
   ```

## 🐛 Troubleshooting

### Nodes not joining cluster
```bash
# Check k3s service on control plane
ansible k3s_server -m shell -a "systemctl status k3s" -b

# Check agent logs
ansible k3s_agents -m shell -a "journalctl -u k3s-agent -n 50" -b
```

### Memory cgroups not enabled
```bash
# Verify cmdline.txt was updated
ansible pis -m shell -a "cat /boot/firmware/cmdline.txt" -b

# Check if reboot happened
ansible pis -m shell -a "uptime"
```

### MetalLB not assigning IPs
```bash
kubectl logs -n metallb-system -l app=metallb
kubectl get ipaddresspool -n metallb-system
```

## 📄 License

MIT
