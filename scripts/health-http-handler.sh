#!/usr/bin/env bash
# scripts/health-http-handler.sh
# Called by socat for each incoming HTTP connection.
# Reads/discards the HTTP request, runs the health check, returns JSON.

set -euo pipefail

# Read and discard HTTP request headers
while IFS= read -r line; do
  line="${line%%$'\r'}"
  [ -z "$line" ] && break
done

# Run the health check script
body=$(/scripts/homelab-health-check.sh 2>/dev/null || echo '{"error":"health check script failed"}')

# Send HTTP response
printf "HTTP/1.1 200 OK\r\n"
printf "Content-Type: application/json\r\n"
printf "Connection: close\r\n"
printf "\r\n"
printf "%s" "$body"
