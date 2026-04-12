#!/usr/bin/env bash
# scripts/homelab-health-check.sh
# Collects Docker service health data and outputs JSON.
# Called by the n8n daily health report workflow via SSH.

set -euo pipefail
cd /home/jmendoza/homelab

# --- HTTP Health Checks ---
declare -A ENDPOINTS=(
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
  ["plex"]="http://localhost:32400/identity"
  ["homepage"]="http://localhost:3001"
)

http_checks="["
first=true
for name in $(echo "${!ENDPOINTS[@]}" | tr ' ' '\n' | sort); do
  url="${ENDPOINTS[$name]}"
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null || echo "000")
  healthy=false
  if [[ "$code" =~ ^[23] ]]; then
    healthy=true
  fi
  if [ "$first" = true ]; then first=false; else http_checks+=","; fi
  http_checks+="{\"service\":\"$name\",\"url\":\"$url\",\"status_code\":$code,\"healthy\":$healthy}"
done
http_checks+="]"

# --- Container Status ---
containers=$(docker compose ps --format json 2>/dev/null | python3 -c "
import sys, json

entries = []
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        c = json.loads(line)
    except json.JSONDecodeError:
        continue
    name = c.get('Name', '')
    state = c.get('State', '')
    health = c.get('Health', '')
    running_for = c.get('RunningFor', '')
    entries.append({'name': name, 'state': state, 'health': health, 'uptime': running_for})
print(json.dumps(entries))
" 2>/dev/null || echo "[]")

# Inject restart counts — rebuild the array with restarts field added
containers=$(echo "$containers" | python3 -c "
import sys, json, subprocess

entries = json.load(sys.stdin)
for e in entries:
    try:
        r = subprocess.run(
            ['docker', 'inspect', '--format', '{{.RestartCount}}', e['name']],
            capture_output=True, text=True, timeout=5
        )
        e['restarts'] = int(r.stdout.strip()) if r.returncode == 0 else 0
    except Exception:
        e['restarts'] = 0
print(json.dumps(entries))
" 2>/dev/null || echo "[]")

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
done < <(df -h / /mnt/synology --output=source,size,used,avail,pcent 2>/dev/null)
disk+="]"

# --- Output ---
cat <<EOF
{"http_checks":$http_checks,"containers":$containers,"disk":$disk}
EOF
