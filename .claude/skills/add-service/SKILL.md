---
name: add-service
description: Add a new Docker Compose service following homelab patterns — covers docker-compose.yml, env file, K3s Service+Endpoints, and HTTPS ingress rule to keep all four in sync
---

# Add New Homelab Service

Adding a service requires updates in **4 places**. Work through each checklist item.

## Information to Gather First

Ask the user for:
1. **Service name** (container name, e.g. `my-service`)
2. **Docker image** (e.g. `org/image:tag`)
3. **Host port** (the port exposed on the host)
4. **Container port** (the port the app listens on inside the container)
5. **Data type**: Does it store large data (models, DBs, documents, books)? → NAS (`/mnt/synology/`). Small config/state only? → Local (`./service-name/data/`)
6. **Subdomain** for HTTPS access (e.g. `myservice.justinmendoza.net`)
7. **Dependencies**: Does it need another container to be running first?

## Step 1: Add to docker-compose.yml

Add this block to `/home/jmendoza/homelab/docker-compose.yml`, following the existing service sections:

```yaml
# ---------------------------
# <Service Name>
# ---------------------------
<service-name>:
  image: <org/image:tag>
  container_name: <service-name>
  labels:
    - "com.centurylinklabs.watchtower.enable=true"
  ports:
    - "<HOST_PORT>:<CONTAINER_PORT>"
  env_file:
    - ./<service-name>/.env
  volumes:
    # Choose based on data type:
    - /mnt/synology/<service-name>/data:/app/data    # Large/persistent (NAS-backed)
    # OR
    - ./<service-name>/data:/app/.config             # Small config/state (local)
  depends_on:                                        # Only if needed
    - <dependency>
  restart: unless-stopped
```

**Critical checks:**
- [ ] Watchtower label is present
- [ ] Uses container names (not `localhost`) for any inter-service URLs in `.env`
- [ ] Volume path matches data type decision

## Step 2: Create .env File

```bash
mkdir -p /home/jmendoza/homelab/<service-name>
touch /home/jmendoza/homelab/<service-name>/.env
touch /home/jmendoza/homelab/<service-name>/.env.example
```

Add `TZ=America/Chicago` as the baseline in both. Add all required env vars to `.env.example` with placeholder values, then fill real values in `.env` (never committed).

## Step 3: Add K3s Service + Endpoints

Add to `/home/jmendoza/homelab/k3s-manifests/docker-services.yaml`:

```yaml
---
# <Service Name> Service & Endpoints
apiVersion: v1
kind: Service
metadata:
  name: <service-name>
  namespace: docker-services
spec:
  ports:
    - port: 80
      targetPort: <HOST_PORT>
      protocol: TCP
---
apiVersion: v1
kind: Endpoints
metadata:
  name: <service-name>
  namespace: docker-services
subsets:
  - addresses:
      - ip: 100.123.171.3
    ports:
      - port: <HOST_PORT>
```

## Step 4: Add HTTPS Ingress Rule

Add to `/home/jmendoza/homelab/k3s-manifests/ingress-routes-https.yaml`:

```yaml
---
# <Service Name> Ingress with HTTPS
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <service-name>
  namespace: docker-services
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
    - hosts:
        - <subdomain>.justinmendoza.net
      secretName: <service-name>-tls
  rules:
    - host: <subdomain>.justinmendoza.net
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <service-name>
                port:
                  number: 80
```

## Step 5: Apply and Verify

```bash
# Start the container
docker compose up -d <service-name>
docker compose logs --tail=50 <service-name>

# Apply K3s changes
export KUBECONFIG=~/.kube/k3s-config
kubectl apply -f k3s-manifests/docker-services.yaml
kubectl apply -f k3s-manifests/ingress-routes-https.yaml

# Verify
kubectl get ingress <service-name> -n docker-services
kubectl get certificate <service-name>-tls -n docker-services
```

TLS cert provisioning takes 1-2 minutes. Check with:
```bash
kubectl describe certificate <service-name>-tls -n docker-services
```
