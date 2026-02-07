# K3s Raspberry Pi Cluster Guide

Comprehensive guide for managing the 4-node Kubernetes cluster with Ansible automation.

## Cluster Architecture

```
┌────────────────────────────────────────────────────────┐
│ Control Plane                                          │
│ ┌──────────────────────────────────────────┐          │
│ │ k3s-cp-01 (192.168.68.80)                │          │
│ │ - K3s server                             │          │
│ │ - etcd                                   │          │
│ │ - API server (6443)                      │          │
│ │ - MetalLB controller                     │          │
│ │ Tainted: NoSchedule (no workload pods)   │          │
│ └──────────────────────────────────────────┘          │
└────────────────────────────────────────────────────────┘
                           ↓
┌────────────────────────────────────────────────────────┐
│ Worker Nodes                                           │
│ ┌──────────────┐ ┌──────────────┐ ┌──────────────┐   │
│ │ k3s-node-01  │ │ k3s-node-02  │ │ k3s-node-03  │   │
│ │ .68.84       │ │ .68.87       │ │ .68.89       │   │
│ │ K3s agent    │ │ K3s agent    │ │ K3s agent    │   │
│ │ kubelet      │ │ kubelet      │ │ kubelet      │   │
│ └──────────────┘ └──────────────┘ └──────────────┘   │
└────────────────────────────────────────────────────────┘
```

### Key Configuration
- **K3s Version**: Latest stable (auto-downloaded)
- **Network**: Flannel CNI (default)
- **Load Balancer**: MetalLB (L2 mode)
- **Service LB**: Disabled (using MetalLB instead)
- **Control Plane**: Tainted to prevent workload scheduling

## Ansible Inventory

Location: [raspberry-pi-setup/pi-k3s-ansible/inventory.ini](../raspberry-pi-setup/pi-k3s-ansible/inventory.ini)

```ini
[k3s_server]
k3s-cp-01 ansible_host=192.168.68.80

[k3s_agents]
k3s-node-01 ansible_host=192.168.68.84
k3s-node-02 ansible_host=192.168.68.87
k3s-node-03 ansible_host=192.168.68.89

[pis:children]
k3s_server
k3s_agents

[pis:vars]
ansible_user=ubuntu
ansible_become=true
```

**Security Note**: After running `setup-ssh-keys.yml`, remove `ansible_password` and `ansible_become_password` from inventory.

## Playbook Execution Workflow

### Decision Tree
```
First time setup?
  └─→ YES → Run setup-ssh-keys.yml (optional but recommended)
            └─→ Run site.yml
                └─→ Edit metalb.yml IP range
                    └─→ Run metalb.yml
                        └─→ Done!

  └─→ NO → What do you need?
            ├─→ Update IP range → Edit metalb.yml → Run metalb.yml
            ├─→ Add new nodes → Update inventory.ini → Run site.yml
            ├─→ Reconfigure cluster → Run site.yml
            └─→ Troubleshoot → See debugging section below
```

### 1. SSH Key Setup (Optional)

**Purpose**: Enable passwordless authentication and improve security

**Location**: `raspberry-pi-setup/pi-k3s-ansible/setup-ssh-keys.yml`

```bash
cd raspberry-pi-setup/pi-k3s-ansible

# Generate SSH key if needed
ssh-keygen -t rsa -b 4096 -C "homelab@cluster"

# Deploy keys to all Pis
ansible-playbook setup-ssh-keys.yml

# Verify connectivity
ansible all -m ping
```

**After success**: Edit `inventory.ini` and remove password lines.

### 2. Main Cluster Installation

**Purpose**: Configure OS, install K3s, join nodes, copy kubeconfig

**Location**: `raspberry-pi-setup/pi-k3s-ansible/site.yml`

```bash
cd raspberry-pi-setup/pi-k3s-ansible
ansible-playbook site.yml
```

**What it does**:
1. **Baseline config** (all Pis):
   - Set hostname to inventory name
   - Install required packages (`curl`, `ca-certificates`, `python3-yaml`)
   - Upgrade all packages
   - Disable WiFi, configure ethernet with DHCP + Google DNS
   - Enable memory cgroups (critical for K3s)
   - Reboot and wait for network

2. **K3s server** (control plane):
   - Install K3s with `--disable servicelb` flag
   - Wait for kubectl to work
   - Read node token for agents
   - Fetch kubeconfig to `~/.kube/k3s-config`
   - Update server IP in kubeconfig

3. **K3s agents** (workers):
   - Install K3s agent
   - Join cluster using server IP + token

4. **Post-install**:
   - Show cluster nodes
   - Taint control plane (optional)

**Duration**: ~10-15 minutes (includes reboot + downloads)

### 3. MetalLB Load Balancer

**Purpose**: Assign external IPs to LoadBalancer services

**Location**: `raspberry-pi-setup/pi-k3s-ansible/metalb.yml`

**CRITICAL**: Edit IP range before running!

```yaml
# metalb.yml
vars:
  metallb_ip_range: "192.168.68.200-192.168.68.220"  # ← Update this!
```

**Requirements**:
- IP range must be on same subnet as Pis
- IPs must NOT be in DHCP pool
- Recommended: Reserve 10-20 IPs

```bash
cd raspberry-pi-setup/pi-k3s-ansible
ansible-playbook metalb.yml
```

**Verification**:
```bash
export KUBECONFIG=~/.kube/k3s-config
kubectl get pods -n metallb-system
# Should show controller + speaker pods running

# Test with demo service
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=LoadBalancer
kubectl get svc nginx
# EXTERNAL-IP should be from your IP range
```

## Kubeconfig Management

### Local Access

After `site.yml` runs, kubeconfig is automatically fetched:

```bash
# Set environment variable
export KUBECONFIG=~/.kube/k3s-config

# Test access
kubectl get nodes -o wide

# Make permanent
echo 'export KUBECONFIG=~/.kube/k3s-config' >> ~/.bashrc
source ~/.bashrc
```

### Multiple Clusters

If you manage multiple clusters:

```bash
# Merge kubeconfigs
KUBECONFIG=~/.kube/config:~/.kube/k3s-config kubectl config view --flatten > ~/.kube/merged-config
mv ~/.kube/merged-config ~/.kube/config

# Switch contexts
kubectl config get-contexts
kubectl config use-context k3s-homelab
```

## Critical Raspberry Pi Requirements

### Memory Cgroups

**Why needed**: K3s requires memory cgroups for container resource limits

**How it's configured** ([site.yml](../raspberry-pi-setup/pi-k3s-ansible/site.yml#L95-L101)):
```yaml
- name: Enable memory cgroups for k3s (critical for Raspberry Pi)
  ansible.builtin.lineinfile:
    path: /boot/firmware/cmdline.txt
    regexp: '^(.*)(\s+)$'
    line: '\1 cgroup_memory=1 cgroup_enable=memory\2'
    backrefs: true
```

**Verification**:
```bash
ansible pis -m shell -a "cat /boot/firmware/cmdline.txt" -b
# Should contain: cgroup_memory=1 cgroup_enable=memory
```

### DNS Configuration

**Why needed**: Raspberry Pi network may not have DNS after reboot

**How it's configured** ([site.yml](../raspberry-pi-setup/pi-k3s-ansible/site.yml#L62-L77)):
- Google DNS (8.8.8.8, 8.8.4.4) added to netplan
- Network wait task after reboot
- DNS resolution test before K3s install

**Manual check**:
```bash
ansible pis -m shell -a "nslookup get.k3s.io" -b
# Should resolve successfully
```

### Post-Reboot Network Stability

**Issue**: Network needs ~30 seconds to fully initialize after reboot

**Solution** ([site.yml](../raspberry-pi-setup/pi-k3s-ansible/site.yml#L106-L118)):
```yaml
- name: Wait for network to be fully up
  ansible.builtin.wait_for:
    host: 8.8.8.8
    port: 53
    timeout: 60

- name: Test DNS resolution
  ansible.builtin.command: nslookup get.k3s.io
  retries: 10
  delay: 5
  until: dns_test.rc == 0
```

## Common Operations

### Cluster Status

```bash
# Quick check
ansible all -m ping

# Detailed node status
export KUBECONFIG=~/.kube/k3s-config
kubectl get nodes -o wide

# System pods
kubectl get pods -A

# Node resources
kubectl top nodes  # Requires metrics-server
```

### Deploy Workload

```bash
# Create deployment
kubectl create deployment my-app --image=nginx --replicas=3

# Expose with LoadBalancer
kubectl expose deployment my-app --port=80 --type=LoadBalancer

# Check external IP
kubectl get svc my-app

# Scale deployment
kubectl scale deployment my-app --replicas=5
```

### Update K3s Version

```bash
cd raspberry-pi-setup/pi-k3s-ansible

# Stop K3s on all nodes
ansible k3s_server -m shell -a "/usr/local/bin/k3s-killall.sh" -b
ansible k3s_agents -m shell -a "/usr/local/bin/k3s-killall.sh" -b

# Remove K3s
ansible pis -m shell -a "/usr/local/bin/k3s-uninstall.sh" -b

# Reinstall (downloads latest)
ansible-playbook site.yml
```

### Add New Node

1. Update inventory:
   ```ini
   [k3s_agents]
   k3s-node-01 ansible_host=192.168.68.84
   k3s-node-02 ansible_host=192.168.68.87
   k3s-node-03 ansible_host=192.168.68.89
   k3s-node-04 ansible_host=192.168.68.90  # New node
   ```

2. Run playbook (only new node will be configured):
   ```bash
   ansible-playbook site.yml --limit k3s-node-04
   ```

3. Verify:
   ```bash
   kubectl get nodes
   ```

## Troubleshooting

### Common Error Patterns

| Error | Cause | Solution |
|-------|-------|----------|
| `Could not resolve host: get.k3s.io` | DNS not configured or network not ready | Verify netplan has DNS, add wait_for + nslookup test |
| `K3s install fails with cgroup error` | Memory cgroups not enabled | Check `/boot/firmware/cmdline.txt`, reboot if missing |
| `Nodes show NotReady` | Network plugin issues or DNS problems | Check `kubectl describe node`, review `/var/log/syslog` |
| `MetalLB no external IP` | IP range conflicts or MetalLB not running | Verify IP pool config, check MetalLB pods |
| `Agent can't join cluster` | Token mismatch or firewall blocking 6443 | Re-run site.yml, check firewall rules |

### Debug Commands

#### Ansible Connectivity
```bash
# Test SSH access
ansible all -m ping

# Check disk space
ansible pis -m shell -a "df -h" -b

# View system logs
ansible pis -m shell -a "journalctl -n 50 --no-pager" -b

# Check K3s service status
ansible k3s_server -m shell -a "systemctl status k3s" -b
ansible k3s_agents -m shell -a "systemctl status k3s-agent" -b
```

#### K3s Server Debugging
```bash
# Check server logs
ansible k3s_server -m shell -a "journalctl -u k3s -n 100 --no-pager" -b

# Verify API server
ansible k3s_server -m shell -a "k3s kubectl get nodes" -b

# Check token
ansible k3s_server -m shell -a "cat /var/lib/rancher/k3s/server/node-token" -b
```

#### K3s Agent Debugging
```bash
# Check agent logs
ansible k3s_agents -m shell -a "journalctl -u k3s-agent -n 100 --no-pager" -b

# Verify agent config
ansible k3s_agents -m shell -a "cat /etc/systemd/system/k3s-agent.service.env" -b

# Test connectivity to server
ansible k3s_agents -m shell -a "curl -k https://192.168.68.80:6443" -b
```

#### Network Debugging
```bash
# Check network config
ansible pis -m shell -a "cat /etc/netplan/*.yaml" -b

# Test DNS
ansible pis -m shell -a "nslookup google.com" -b

# Check IP addresses
ansible pis -m shell -a "ip addr show eth0" -b

# Verify cgroups
ansible pis -m shell -a "cat /boot/firmware/cmdline.txt" -b
```

#### MetalLB Issues
```bash
# Check MetalLB pods
kubectl get pods -n metallb-system

# View controller logs
kubectl logs -n metallb-system -l app=metallb,component=controller

# View speaker logs (on each node)
kubectl logs -n metallb-system -l app=metallb,component=speaker

# Check IP pools
kubectl get ipaddresspool -n metallb-system -o yaml

# Check L2 advertisements
kubectl get l2advertisement -n metallb-system -o yaml
```

### Recovery Procedures

#### Cluster Not Responding
```bash
# 1. Check if nodes are powered on
ansible all -m ping

# 2. Restart K3s services
ansible k3s_server -m shell -a "systemctl restart k3s" -b
ansible k3s_agents -m shell -a "systemctl restart k3s-agent" -b

# 3. If still failing, full reinstall
ansible-playbook site.yml
```

#### Node Stuck in NotReady
```bash
# 1. Drain node
kubectl drain k3s-node-02 --ignore-daemonsets --delete-emptydir-data

# 2. Restart node
ansible k3s-node-02 -m reboot -b

# 3. Wait for node to rejoin
kubectl get nodes -w

# 4. Uncordon node
kubectl uncordon k3s-node-02
```

#### MetalLB Not Assigning IPs
```bash
# 1. Check IP pool is correct
kubectl get ipaddresspool -n metallb-system -o yaml

# 2. Update if needed
ansible-playbook metalb.yml

# 3. Restart MetalLB
kubectl rollout restart deployment -n metallb-system controller
kubectl rollout restart daemonset -n metallb-system speaker
```

## Ansible Playbook Patterns

### Idempotency Best Practices

**Use `creates:` for installations**:
```yaml
- name: Install k3s server
  ansible.builtin.shell: |
    curl -sfL https://get.k3s.io | sh -s - {{ k3s_install_flags }}
  args:
    creates: /usr/local/bin/k3s  # Only runs if file doesn't exist
```

**Add `changed_when` for status commands**:
```yaml
- name: Show nodes
  ansible.builtin.shell: k3s kubectl get nodes -o wide
  register: nodes_out
  changed_when: false  # This command doesn't change anything
```

**Use retries for network operations**:
```yaml
- name: Test DNS resolution
  ansible.builtin.command: nslookup get.k3s.io
  register: dns_test
  retries: 10
  delay: 5
  until: dns_test.rc == 0
```

### Local File Operations

When fetching files to local machine:

```yaml
- name: Fetch kubeconfig to local machine
  ansible.builtin.fetch:
    src: /etc/rancher/k3s/k3s.yaml
    dest: ~/.kube/k3s-config
    flat: true

- name: Update kubeconfig server address
  ansible.builtin.replace:
    path: ~/.kube/k3s-config
    regexp: 'https://127\.0\.0\.1:6443'
    replace: 'https://{{ ansible_host }}:6443'
  delegate_to: localhost  # Run on local machine
  become: false           # Don't use sudo
```

## Advanced Topics

### Custom K3s Flags

Edit `site.yml` to modify K3s installation:

```yaml
vars:
  k3s_install_flags: >-
    --write-kubeconfig-mode 644
    --disable servicelb
    --disable traefik          # Add: disable built-in ingress
    --node-taint CriticalAddonsOnly=true:NoExecute  # Add: stronger taint
```

### Storage Configuration

K3s includes local-path provisioner by default:

```bash
# Check storage class
kubectl get storageclass

# Create persistent volume claim
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
EOF
```

For distributed storage, consider installing Longhorn:

```bash
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml
```

### Ingress Controller

Install NGINX Ingress:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml

# MetalLB will assign external IP
kubectl get svc -n ingress-nginx
```

### Monitoring Stack

Deploy Prometheus + Grafana:

```bash
# Add Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install kube-prometheus-stack
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace
```

## Quick Reference

### Essential Playbook Commands
```bash
cd raspberry-pi-setup/pi-k3s-ansible

# Full setup sequence
ansible-playbook setup-ssh-keys.yml  # Optional
ansible-playbook site.yml            # Main install
ansible-playbook metalb.yml          # Load balancer

# Testing
ansible all -m ping                  # Connectivity
ansible all -m shell -a "uptime"     # Quick status

# Debugging
ansible k3s_server -m shell -a "k3s kubectl get nodes" -b
ansible k3s_agents -m shell -a "journalctl -u k3s-agent -n 50" -b
```

### Essential kubectl Commands
```bash
export KUBECONFIG=~/.kube/k3s-config

# Cluster info
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info

# Deploy workload
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=LoadBalancer
kubectl get svc

# Troubleshooting
kubectl describe node k3s-node-01
kubectl logs -n kube-system <pod-name>
kubectl get events --sort-by='.lastTimestamp'
```

### File Locations Reference

| File | Purpose |
|------|---------|
| [inventory.ini](../raspberry-pi-setup/pi-k3s-ansible/inventory.ini) | Node IPs and credentials |
| [site.yml](../raspberry-pi-setup/pi-k3s-ansible/site.yml) | Main cluster installation |
| [metalb.yml](../raspberry-pi-setup/pi-k3s-ansible/metalb.yml) | Load balancer setup |
| [setup-ssh-keys.yml](../raspberry-pi-setup/pi-k3s-ansible/setup-ssh-keys.yml) | SSH key deployment |
| ~/.kube/k3s-config | Local kubeconfig (auto-fetched) |
| /boot/firmware/cmdline.txt | Raspberry Pi boot config (cgroups) |
| /etc/netplan/*.yaml | Network configuration |
