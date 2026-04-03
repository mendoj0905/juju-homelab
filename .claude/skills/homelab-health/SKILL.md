---
name: homelab-health
description: Full health check for all homelab services — HTTP endpoint checks for Docker services (catches hung-but-running containers) and K3s cluster node/pod status
---

# Homelab Health Check

Run a complete health check across all Docker services and the K3s cluster. Check actual HTTP endpoints — not just container status — because containers can show "Up" while the web server is hung.

## Docker Services — HTTP Health Checks

Run these curl checks sequentially. A 200 (or redirect) = healthy. Connection refused or timeout = down.

```bash
echo "=== Docker Service Health ==="
declare -A SERVICES=(
  ["dozzle"]="http://localhost:8080"
  ["paperless"]="http://localhost:8001/api/"
  ["paperless-ai"]="http://localhost:8002"
  ["paperless-gpt"]="http://localhost:8003"
  ["open-webui"]="http://localhost:3000"
  ["ollama"]="http://localhost:11434/api/tags"
  ["open-notebook"]="http://localhost:8502"
  ["surrealdb"]="http://localhost:8000/health"
  ["calibre"]="http://localhost:8084"
  ["calibre-web"]="http://localhost:8083"
  ["homeassistant"]="http://localhost:8123"
  ["zigbee2mqtt"]="http://localhost:8090"
)

for name in "${!SERVICES[@]}"; do
  url="${SERVICES[$name]}"
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null)
  if [[ "$code" =~ ^[23] ]]; then
    echo "  ✓ $name ($code)"
  else
    echo "  ✗ $name — HTTP $code (url: $url)"
  fi
done
```

Then check container state for any service that failed HTTP:
```bash
docker compose ps
```

## K3s Cluster Health

```bash
echo ""
echo "=== K3s Cluster ==="
export KUBECONFIG=~/.kube/k3s-config
kubectl get nodes -o wide
echo ""
echo "--- Unhealthy Pods ---"
kubectl get pods --all-namespaces --field-selector='status.phase!=Running,status.phase!=Succeeded' 2>/dev/null || echo "All pods healthy"
```

## Interpreting Results

- **Container "Up" but HTTP ✗**: Service is hung. Run `docker compose restart <service>` to fix.
- **Node NotReady**: Check `kubectl describe node <name>` for reason.
- **Pod CrashLoopBackOff**: Run `kubectl logs -n <namespace> <pod>` for details.
- **Recurring hung services**: Check logs before restart — a blocking integration (e.g., Kasa timeout) may need to be disabled.
