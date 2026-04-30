#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
HOMELAB_DIR="/home/jmendoza/development/homelab"
LOG_FILE="/home/jmendoza/homelab-health.log"
CLAUDE_BIN="/home/jmendoza/.local/bin/claude"

# Load secrets from env file if present, otherwise expect them in environment
ENV_FILE="$HOMELAB_DIR/.env.cron"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is not set}"
: "${DISCORD_WEBHOOK:?DISCORD_WEBHOOK is not set}"

export ANTHROPIC_API_KEY
export DISCORD_WEBHOOK
export KUBECONFIG="/home/jmendoza/.kube/k3s-config"

# --- Run ---
cd "$HOMELAB_DIR"

exec >> "$LOG_FILE" 2>&1
echo ""
echo "=== $(date -u '+%Y-%m-%d %H:%M:%S UTC') ==="

"$CLAUDE_BIN" --bare -p \
  "You are running an automated homelab health check. Do the following steps in order:

1. Check each Docker service HTTP endpoint and report ✓ or ✗:
   - dozzle:        http://localhost:8080
   - paperless:     http://localhost:8001/api/
   - paperless-ai:  http://localhost:8002
   - paperless-gpt: http://localhost:8003
   - open-webui:    http://localhost:3000
   - ollama:        http://localhost:11434/api/tags
   - calibre:       http://localhost:8084
   - calibre-web:   http://localhost:8083
   - homeassistant: http://localhost:8123
   - zigbee2mqtt:   http://localhost:8090
   Use curl with --connect-timeout 5. A 2xx or 3xx response is healthy.

2. Check K3s cluster: node status and any non-Running/Succeeded pods across all namespaces.

3. Post a summary to Discord using:
   curl -X POST \"\$DISCORD_WEBHOOK\" \\
     -H 'Content-Type: application/json' \\
     -d '{\"content\": \"<message>\"}'

   Format the Discord message as:
   **Homelab Health — <date>**

   **Docker**
   ✓ service-name
   ✗ service-name — HTTP <code>

   **K3s**
   ✓ All nodes Ready / or list issues

   If anything is unhealthy, prepend the message with @here.
   Keep it concise — this posts to a Discord channel." \
  --allowedTools "Bash"

echo "Done."
