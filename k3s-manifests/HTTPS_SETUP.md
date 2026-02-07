# HTTPS Setup Guide

## Step 1: Create Cloudflare API Token

1. Go to https://dash.cloudflare.com/profile/api-tokens
2. Click **Create Token**
3. Use template **Edit zone DNS** OR create custom token with:
   - Permissions: `Zone - DNS - Edit`
   - Zone Resources: `Include - Specific zone - justinmendoza.net`
4. Copy the token

## Step 2: Update cert-manager-setup.yaml

Edit `k3s-manifests/cert-manager-setup.yaml`:
- Replace `YOUR_CLOUDFLARE_API_TOKEN_HERE` with your token
- Replace `your-email@example.com` with your email (for Let's Encrypt notifications)

## Step 3: Install cert-manager

```bash
export KUBECONFIG=~/.kube/k3s-config

# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.2/cert-manager.yaml

# Wait for cert-manager to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=120s

# Apply your configuration
kubectl apply -f k3s-manifests/cert-manager-setup.yaml
```

## Step 4: Enable HTTPS on Traefik

Update port forwarding to include HTTPS:

```bash
cd raspberry-pi-setup/pi-k3s-ansible
ansible k3s-cp-01 -m shell -a "sudo iptables -t nat -A PREROUTING -i tailscale0 -p tcp --dport 443 -j DNAT --to-destination 192.168.68.200:443" -b
ansible k3s-cp-01 -m shell -a "sudo iptables -t nat -A POSTROUTING -d 192.168.68.200 -p tcp --dport 443 -j MASQUERADE" -b
```

## Step 5: Deploy HTTPS Ingresses (Staging First)

```bash
# Apply HTTPS ingresses with staging certificates (for testing)
kubectl apply -f k3s-manifests/ingress-routes-https.yaml

# Check certificate status
kubectl get certificate -n docker-services
kubectl describe certificate openwebui-tls -n docker-services
```

## Step 6: Test with Staging Certificates

Wait 1-2 minutes, then test:

```bash
curl -k https://openwebui.justinmendoza.net
# Should work but show certificate warning (expected with staging)
```

## Step 7: Switch to Production Certificates

Once staging works, update `ingress-routes-https.yaml`:
- Change all `letsencrypt-staging` to `letsencrypt-prod`

```bash
# Update annotation in all ingresses
sed -i 's/letsencrypt-staging/letsencrypt-prod/g' k3s-manifests/ingress-routes-https.yaml

# Reapply
kubectl apply -f k3s-manifests/ingress-routes-https.yaml

# Delete old staging certificates to force renewal
kubectl delete certificate --all -n docker-services

# Wait for new certificates
kubectl get certificate -n docker-services -w
```

## Step 8: Verify HTTPS

```bash
curl https://openwebui.justinmendoza.net
# Should work without -k flag and show valid certificate
```

## Troubleshooting

**Certificate stuck in "Pending":**
```bash
kubectl describe certificate <cert-name> -n docker-services
kubectl describe challenge -n docker-services
kubectl logs -n cert-manager -l app=cert-manager
```

**DNS-01 challenge failed:**
- Verify Cloudflare API token has correct permissions
- Check token is correctly set in the secret
- Verify domain ownership in Cloudflare

**Traefik not serving HTTPS:**
- Ensure port 443 is forwarded correctly
- Check Traefik service: `kubectl get svc -n kube-system traefik`
