# HTTPS Setup for n8n with Let's Encrypt

Complete guide to accessing n8n via HTTPS with automatic SSL certificates.

## Prerequisites

✅ **Already configured in your cluster:**
- cert-manager installed
- ClusterIssuer `letsencrypt-prod` configured with Cloudflare DNS01
- Traefik ingress controller

## Setup Steps

### 1. Configure Cloudflare DNS

**Add A record pointing to your Traefik ingress:**

```bash
# First, get your Traefik LoadBalancer IP
kubectl get svc -n kube-system traefik
```

**In Cloudflare DNS:**
1. Go to your domain: `justinmendoza.net`
2. Add DNS record:
   - **Type**: A
   - **Name**: n8n
   - **IPv4 address**: `<TRAEFIK-EXTERNAL-IP>` (from command above)
   - **Proxy status**: 🟠 DNS only (turn OFF Cloudflare proxy)
   - **TTL**: Auto

⚠️ **Important**: DNS must be set to "DNS only" (not proxied) for Let's Encrypt to work properly.

### 2. Apply Updated Manifests

```bash
# Apply the HTTPS middleware
kubectl apply -f k3s-manifests/n8n/middleware.yaml

# Reapply n8n service and ingress
kubectl apply -f k3s-manifests/n8n/service.yaml
kubectl apply -f k3s-manifests/n8n/ingress.yaml
```

### 3. Verify Certificate Issuance

```bash
# Watch certificate creation
kubectl get certificate -n n8n -w

# Should show:
# NAME      READY   SECRET     AGE
# n8n-tls   True    n8n-tls    1m

# Check certificate details
kubectl describe certificate n8n-tls -n n8n

# Check for any cert-manager errors
kubectl logs -n cert-manager -l app=cert-manager -f
```

Certificate issuance typically takes 1-3 minutes.

### 4. Access n8n

Once the certificate shows `READY=True`:

**URL**: https://n8n.justinmendoza.net

✅ **Valid SSL certificate**  
✅ **Automatic HTTP → HTTPS redirect**  
✅ **Auto-renewal before expiry**

## Troubleshooting

### Certificate Stuck in "False" State

```bash
# Check certificate status
kubectl describe certificate n8n-tls -n n8n

# Check certificate request
kubectl get certificaterequest -n n8n
kubectl describe certificaterequest -n n8n <name>

# Check challenge
kubectl get challenge -n n8n
kubectl describe challenge -n n8n <name>
```

**Common issues:**
- DNS not yet propagated (wait 5-10 minutes)
- Cloudflare API token invalid/expired
- DNS record still proxied (must be DNS only)

### Update Cloudflare API Token

If you need to update the token:

```bash
# Edit the secret
kubectl edit secret cloudflare-api-token -n cert-manager

# Or recreate it
kubectl delete secret cloudflare-api-token -n cert-manager
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token='YOUR_NEW_TOKEN' \
  -n cert-manager

# Then delete the certificate to retry
kubectl delete certificate n8n-tls -n n8n
kubectl apply -f k3s-manifests/n8n/ingress.yaml
```

### Test with Staging First (Optional)

To avoid Let's Encrypt rate limits while testing:

```bash
# Edit ingress.yaml and change:
cert-manager.io/cluster-issuer: "letsencrypt-staging"

# Apply and test
kubectl apply -f k3s-manifests/n8n/ingress.yaml

# Browser will show "invalid certificate" but that's expected
# Once working, switch back to letsencrypt-prod
```

### Check Traefik Routing

```bash
# Get traefik pod
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik

# Check logs
kubectl logs -n kube-system <traefik-pod-name>

# Verify ingress is registered
kubectl get ingress -n n8n
```

## Architecture

```
Internet
    ↓
DNS: n8n.justinmendoza.net → <TRAEFIK-IP>
    ↓
Traefik Ingress (port 443)
    ↓ TLS termination
n8n Service (ClusterIP)
    ↓
n8n Pod (port 5678)
```

## Certificate Renewal

cert-manager automatically renews certificates 30 days before expiry. No action needed!

To force renewal:
```bash
kubectl delete secret n8n-tls -n n8n
# Certificate will be automatically recreated
```

## Switching Back to LoadBalancer (If Needed)

If you prefer direct access without ingress:

```bash
# Edit service.yaml
# Change type: ClusterIP → type: LoadBalancer

kubectl apply -f k3s-manifests/n8n/service.yaml
kubectl get svc -n n8n  # Get new external IP

# Update DNS to point to this IP instead of Traefik
```

## Security Notes

- ✅ TLS 1.2+ enforced by Traefik
- ✅ Automatic HTTPS redirect
- ✅ Certificate auto-renewal
- 🔒 Consider enabling n8n authentication (see main README)
- 🔒 Use Cloudflare firewall rules to restrict access if needed

## Next Steps

After HTTPS is working:

1. **Enable n8n authentication** - Edit deployment, add basic auth env vars
2. **Set up OAuth** - Configure Google/GitHub login
3. **Configure webhooks** - Use `https://n8n.justinmendoza.net/webhook/...`
4. **Set up monitoring** - Add Grafana dashboard for n8n metrics
