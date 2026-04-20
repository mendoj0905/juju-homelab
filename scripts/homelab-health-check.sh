#!/usr/bin/env bash
# scripts/homelab-health-check.sh
# Collects Docker service health data and outputs JSON.
# Called by the n8n daily health report workflow via SSH.

set -euo pipefail

# --- HTTP Health Checks ---
# Use container names (Docker network) when running inside a container,
# or localhost when running directly on the host.
declare -A ENDPOINTS=(
  ["dozzle"]="http://dozzle:8080"
  ["paperless"]="http://paperless:8000/api/"
  ["paperless-ai"]="http://paperless-ai:3000"
  ["paperless-gpt"]="http://paperless-gpt:8080"
  ["open-webui"]="http://open-webui:8080"
  ["ollama"]="http://ollama:11434/api/tags"
  ["open-notebook"]="http://open-notebook:8502"
  ["surrealdb"]="http://surrealdb:8000/health"
  ["calibre"]="http://calibre:8080"
  ["calibre-web"]="http://calibre-web:8083"
  ["homeassistant"]="http://homeassistant:8123"
  ["plex"]="http://plex:32400/identity"
  ["homepage"]="http://homepage:3000"
)

http_checks="["
first=true
for name in $(echo "${!ENDPOINTS[@]}" | tr ' ' '\n' | sort); do
  url="${ENDPOINTS[$name]}"
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null || true)
  code=${code:-0}
  # Ensure it's a valid number
  if ! [[ "$code" =~ ^[0-9]+$ ]]; then code=0; fi
  healthy=false
  if [[ "$code" =~ ^[23] ]]; then
    healthy=true
  fi
  if [ "$first" = true ]; then first=false; else http_checks+=","; fi
  http_checks+="{\"service\":\"$name\",\"url\":\"$url\",\"status_code\":$code,\"healthy\":$healthy}"
done
http_checks+="]"

# --- Container Status ---
containers="["
first=true
while IFS= read -r line; do
  [ -z "$line" ] && continue
  cname=$(echo "$line" | sed 's/|.*//')
  cstate=$(echo "$line" | cut -d'|' -f2)
  chealth=$(echo "$line" | cut -d'|' -f3)
  cuptime=$(echo "$line" | cut -d'|' -f4)
  restarts=$(docker inspect --format '{{.RestartCount}}' "$cname" 2>/dev/null || echo "0")
  if [ "$first" = true ]; then first=false; else containers+=","; fi
  containers+="{\"name\":\"$cname\",\"state\":\"$cstate\",\"health\":\"$chealth\",\"uptime\":\"$cuptime\",\"restarts\":$restarts}"
done < <(docker ps -a --format '{{.Names}}|{{.State}}|{{.Status}}|{{.RunningFor}}' --filter "label=com.docker.compose.project=homelab" 2>/dev/null)
containers+="]"

# --- Disk Usage ---
disk="["
first=true
while IFS= read -r line; do
  # Skip header
  if echo "$line" | grep -q "Filesystem\|Source"; then continue; fi
  fs=$(echo "$line" | awk '{print $1}')
  size=$(echo "$line" | awk '{print $2}')
  used=$(echo "$line" | awk '{print $3}')
  avail=$(echo "$line" | awk '{print $4}')
  pct=$(echo "$line" | awk '{print $5}')
  if [ "$first" = true ]; then first=false; else disk+=","; fi
  disk+="{\"filesystem\":\"$fs\",\"size\":\"$size\",\"used\":\"$used\",\"available\":\"$avail\",\"percent\":\"$pct\"}"
done < <(df -h / /mnt/synology --output=source,size,used,avail,pcent 2>/dev/null || df -h / /mnt/synology 2>/dev/null || df -h / 2>/dev/null)
disk+="]"

# --- K3s Cluster Data ---
k3s_nodes="[]"
k3s_unhealthy_pods="[]"
k3s_certs="[]"

if command -v kubectl &>/dev/null && [ -f /root/.kube/config ]; then
  export KUBECONFIG=/root/.kube/config

  # Nodes
  k3s_nodes="["
  first=true
  while IFS='|' read -r name status ip version; do
    [ -z "$name" ] && continue
    if [ "$first" = true ]; then first=false; else k3s_nodes+=","; fi
    k3s_nodes+="{\"name\":\"$name\",\"status\":\"$status\",\"ip\":\"$ip\",\"version\":\"$version\"}"
  done < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}|{range .status.conditions[?(@.type=="Ready")]}{.status}{end}|{range .status.addresses[?(@.type=="InternalIP")]}{.address}{end}|{.status.nodeInfo.kubeletVersion}{"\n"}{end}' 2>/dev/null | sed 's/True/Ready/;s/False/NotReady/')
  k3s_nodes+="]"

  # Unhealthy pods
  k3s_unhealthy_pods="["
  first=true
  while IFS='|' read -r ns name phase reason; do
    [ -z "$name" ] && continue
    reason=${reason:-unknown}
    if [ "$first" = true ]; then first=false; else k3s_unhealthy_pods+=","; fi
    k3s_unhealthy_pods+="{\"namespace\":\"$ns\",\"name\":\"$name\",\"phase\":\"$phase\",\"reason\":\"$reason\"}"
  done < <(kubectl get pods --all-namespaces --field-selector='status.phase!=Running,status.phase!=Succeeded' -o jsonpath='{range .items[*]}{.metadata.namespace}|{.metadata.name}|{.status.phase}|{.status.reason}{"\n"}{end}' 2>/dev/null)
  k3s_unhealthy_pods+="]"

  # TLS certificates (cert-manager)
  k3s_certs="["
  first=true
  now_epoch=$(date +%s)
  while IFS='|' read -r ns name ready notafter; do
    [ -z "$name" ] && continue
    days=""
    expiring_soon=false
    if [ -n "$notafter" ]; then
      cert_epoch=$(date -d "$notafter" +%s 2>/dev/null || echo "0")
      if [ "$cert_epoch" != "0" ]; then
        days=$(( (cert_epoch - now_epoch) / 86400 ))
        if [ "$days" -le 14 ]; then expiring_soon=true; fi
      fi
    fi
    if [ "$first" = true ]; then first=false; else k3s_certs+=","; fi
    k3s_certs+="{\"namespace\":\"$ns\",\"name\":\"$name\",\"ready\":$ready,\"notAfter\":\"${notafter:-unknown}\",\"daysUntilExpiry\":${days:-null},\"expiringSoon\":$expiring_soon}"
  done < <(kubectl get certificates --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}|{.metadata.name}|{range .status.conditions[?(@.type=="Ready")]}{.status}{end}|{.status.notAfter}{"\n"}{end}' 2>/dev/null | sed 's/|True|/|true|/;s/|False|/|false|/')
  k3s_certs+="]"
fi

# --- Output ---
cat <<EOF
{"http_checks":$http_checks,"containers":$containers,"disk":$disk,"k3s":{"nodes":$k3s_nodes,"unhealthy_pods":$k3s_unhealthy_pods,"certificates":$k3s_certs}}
EOF
