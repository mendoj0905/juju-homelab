# NFS Storage Provisioner for K3s

Enables K3s workloads to use your Synology NAS for persistent storage.

## Prerequisites

### 1. Configure Synology NAS

**Enable NFS Service:**
1. Open Synology DSM
2. Go to **Control Panel** > **File Services** > **NFS**
3. Check **Enable NFS service**
4. Click **Apply**

**Create Shared Folder:**
1. Go to **Control Panel** > **Shared Folder**
2. Create new folder: `k3s`
3. Note the path: `/volume2/k3s`

**Set NFS Permissions:**
1. Select the `k3s` folder
2. Click **Edit** > **NFS Permissions**
3. Click **Create**
4. Configure:
   - **Server or IP address**: `192.168.68.0/24` (your Pi subnet)
   - **Privilege**: Read/Write
   - **Squash**: Map all users to admin
   - **Security**: sys
   - **Enable asynchronous**: ✓ (optional, better performance)
5. Click **OK**

### 2. Verify NFS Access

Test from your workstation or a Pi:
```bash
# Install NFS client
sudo apt install nfs-common

# Test connection
showmount -e 192.168.68.10  # Replace with your Synology IP

# Should show:
# Export list for 192.168.68.10:
# /volume1/k3s 192.168.68.0/24
```

## Installation

### Option 1: Ansible Playbook (Recommended)

This automates everything - NFS client installation on Pis and provisioner deployment.

```bash
cd raspberry-pi-setup/pi-k3s-ansible

# Edit variables first!
nano nfs-storage.yml
# Update:
# - nfs_server: "192.168.68.10"  # Your Synology IP
# - nfs_path: "/volume1/k3s"      # Your NFS export path

# Run playbook
ansible-playbook nfs-storage.yml
```

### Option 2: Manual Deployment

If you already have NFS clients installed on the Pis:

```bash
# Update deployment.yaml with your NFS server IP and path
nano k3s-manifests/nfs-provisioner/deployment.yaml

# Deploy
export KUBECONFIG=~/.kube/k3s-config
kubectl apply -f k3s-manifests/nfs-provisioner/

# Verify
kubectl get pods -n nfs-provisioner
kubectl get storageclass
```

## Usage

### Create PVC Using NFS Storage

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-data
  namespace: my-namespace
spec:
  accessModes:
    - ReadWriteMany  # NFS supports RWX!
  storageClassName: nfs-synology
  resources:
    requests:
      storage: 5Gi
```

### Key Features

**ReadWriteMany (RWX)**: Multiple pods on different nodes can mount the same volume simultaneously - great for shared data.

**Archive on Delete**: When you delete a PVC, data is moved to `archived-<pvc-name>-<namespace>` folder on the NAS instead of being deleted.

**Volume Expansion**: You can increase PVC size without recreating it.

## Storage Classes Available

After setup, you'll have:

| Name | Type | Default | Use Case |
|------|------|---------|----------|
| `local-path` | Local | Yes | Fast, node-local storage |
| `nfs-synology` | NFS | No | Shared storage, backed up to NAS |

To make NFS default (optional):
```bash
# Remove default from local-path
kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'

# Make NFS default
kubectl patch storageclass nfs-synology -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

## Update Existing Workloads

### n8n Example

The n8n PVC needs to be updated to use NFS:

```bash
# Delete existing PVC (data will be lost if not backed up!)
kubectl delete pvc n8n-data -n n8n

# Update PVC to use NFS
kubectl apply -f k3s-manifests/n8n/pvc.yaml

# Restart deployment
kubectl rollout restart deployment/n8n -n n8n
```

## Troubleshooting

### Provisioner Pod Not Starting

```bash
kubectl describe pod -n nfs-provisioner -l app=nfs-client-provisioner
kubectl logs -n nfs-provisioner -l app=nfs-client-provisioner
```

**Common issues:**
- NFS server unreachable: Check firewall, verify `showmount -e <NFS_SERVER>`
- Permission denied: Check Synology NFS permissions include your Pi subnet
- Mount failed: Ensure NFS client packages installed on all Pis

### PVC Stuck in Pending

```bash
kubectl describe pvc <pvc-name> -n <namespace>
```

**Common issues:**
- Provisioner not running: Check `kubectl get pods -n nfs-provisioner`
- Wrong StorageClass name: Verify `kubectl get storageclass`
- NFS mount issues: Check provisioner pod logs

### Test NFS Mount Manually

SSH to any Pi and test:
```bash
sudo mkdir -p /mnt/test-nfs
sudo mount -t nfs 192.168.68.10:/volume1/k3s /mnt/test-nfs
ls -la /mnt/test-nfs
sudo umount /mnt/test-nfs
```

## Data Location on NAS

When you create a PVC, data is stored at:
```
/volume1/k3s/<namespace>-<pvc-name>-<pv-name>/
```

Example:
```
/volume1/k3s/n8n-n8n-data-pvc-abc123/
```

When deleted (with archiveOnDelete):
```
/volume1/k3s/archived-n8n-n8n-data-pvc-abc123/
```

## Performance Notes

**NFS vs Local Storage:**
- **NFS**: Slower, network-dependent, but shared and backed up
- **Local**: Faster, but data only on one node, not backed up

**Best practices:**
- Use NFS for: Configuration, user data, shared files, anything you want backed up
- Use local-path for: Temporary data, cache, logs, performance-critical databases

## Uninstall

```bash
# Delete provisioner
kubectl delete -f k3s-manifests/nfs-provisioner/

# Remove NFS client from Pis (optional)
ansible pis -m apt -a "name=nfs-common state=absent" -b
```

Data on Synology NAS will remain untouched.
