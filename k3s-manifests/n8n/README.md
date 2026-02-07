# n8n Deployment on K3s

Workflow automation tool deployed to the Raspberry Pi K3s cluster.

## Quick Start

```bash
# Deploy all manifests
export KUBECONFIG=~/.kube/k3s-config
kubectl apply -f namespace.yaml
kubectl apply -f pvc.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# Or apply all at once
kubectl apply -f .
```

## Access n8n

### Via LoadBalancer (Default)
```bash
# Get external IP assigned by MetalLB
kubectl get svc -n n8n n8n

# Access at: http://<EXTERNAL-IP>:5678
# Or configure DNS: n8n.justinmendoza.net -> <EXTERNAL-IP>
```

### Via Ingress (Optional)
If you prefer using an Ingress controller:

1. Change `service.yaml` type from `LoadBalancer` to `ClusterIP`
2. Apply `ingress.yaml`
3. Ensure your ingress controller is configured

## Configuration

### Environment Variables
Edit `deployment.yaml` to customize:
- `N8N_HOST`: Your domain name
- `WEBHOOK_URL`: External webhook endpoint
- `GENERIC_TIMEZONE`: Your timezone

### Enable Authentication
Uncomment the basic auth environment variables in `deployment.yaml`:
```yaml
- name: N8N_BASIC_AUTH_ACTIVE
  value: "true"
- name: N8N_BASIC_AUTH_USER
  value: "admin"
- name: N8N_BASIC_AUTH_PASSWORD
  value: "changeme"  # CHANGE THIS!
```

### Storage
- Default: 10Gi local-path storage
- Data persists at `/home/node/.n8n` inside container
- Backed by K3s local-path provisioner on worker nodes

## Connecting to Docker Services

n8n can connect to services on your GPU host over the network:

```javascript
// In n8n HTTP Request nodes:
// Ollama
http://192.168.68.XX:11434/api/generate

// Open-WebUI
http://192.168.68.XX:3000

// Paperless
http://192.168.68.XX:8001/api/
```

Replace `192.168.68.XX` with your GPU host's IP address.

## Useful Commands

```bash
# Check pod status
kubectl get pods -n n8n

# View logs
kubectl logs -n n8n -l app=n8n -f

# Restart deployment
kubectl rollout restart deployment/n8n -n n8n

# Access pod shell
kubectl exec -it -n n8n deployment/n8n -- /bin/sh

# Check persistent volume
kubectl get pvc -n n8n
kubectl describe pvc n8n-data -n n8n

# Delete everything
kubectl delete -f .
```

## Troubleshooting

### Pod Not Starting
```bash
kubectl describe pod -n n8n -l app=n8n
kubectl logs -n n8n -l app=n8n
```

### No External IP Assigned
Verify MetalLB is running:
```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
```

### Storage Issues
```bash
# Check PVC status
kubectl get pvc -n n8n

# Check node where pod is scheduled
kubectl get pod -n n8n -o wide

# Verify local-path provisioner
kubectl get sc
```

## Upgrading

```bash
# Update to latest image
kubectl set image deployment/n8n n8n=n8nio/n8n:latest -n n8n

# Or edit deployment.yaml and reapply
kubectl apply -f deployment.yaml
```

## Backup

```bash
# Export workflows (from n8n UI or CLI)
# Data is stored in PVC on worker node

# Find which node hosts the PVC
kubectl get pvc -n n8n n8n-data -o yaml | grep volumeName

# SSH to that node and backup
# Default path: /var/lib/rancher/k3s/storage/<pv-name>
```

## Integration Examples

### Workflow: Query Ollama
1. Create HTTP Request node
2. Method: POST
3. URL: `http://192.168.68.XX:11434/api/generate`
4. Body:
   ```json
   {
     "model": "llama3.2:8b",
     "prompt": "Hello, how are you?",
     "stream": false
   }
   ```

### Workflow: Upload to Paperless
1. Create HTTP Request node
2. Method: POST
3. URL: `http://192.168.68.XX:8001/api/documents/post_document/`
4. Authentication: Add API token header
5. Body: Attach file

## Security Notes

- ⚠️ Enable authentication before exposing to internet
- Consider using secrets for sensitive environment variables
- Use HTTPS with cert-manager for production
- Restrict network access using NetworkPolicies if needed
