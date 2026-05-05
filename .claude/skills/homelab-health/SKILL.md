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
check() {
  name="$1"; url="$2"
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null)
  if [[ "$code" =~ ^[23] ]]; then echo "  ✓ $name ($code)"; else echo "  ✗ $name — HTTP $code"; fi
}
check dozzle        "http://localhost:8080"
check paperless     "http://localhost:8001/api/"
check paperless-ai  "http://localhost:8002"
check paperless-gpt "http://localhost:8003"
check open-webui    "http://localhost:3000"
check ollama        "http://localhost:11434/api/tags"
check calibre       "http://localhost:8084"
check calibre-web   "http://localhost:8083"
check homeassistant "http://localhost:8123"
check zigbee2mqtt   "http://localhost:8090"
check homepage      "http://localhost:3001"
check plex          "http://localhost:32400/web"
check sonarr        "http://localhost:8989"
check radarr        "http://localhost:7878"
check prowlarr      "http://localhost:9696"
check qbittorrent   "http://localhost:8081"
check sabnzbd       "http://localhost:8082"
check bazarr        "http://localhost:6767"
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
