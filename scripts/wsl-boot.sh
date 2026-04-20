#!/usr/bin/env bash
# WSL boot-time initialization. Called by wsl.conf [boot] command=.
# Runs as root.
set -euo pipefail

LOG="/var/log/wsl-boot.log"
exec >> "$LOG" 2>&1
echo "=== wsl-boot.sh started at $(date -Iseconds) ==="

modprobe cp210x && echo "cp210x module loaded" || echo "WARN: cp210x modprobe failed"

echo "=== wsl-boot.sh finished at $(date -Iseconds) ==="

  service ssh start && echo "sshd started" || echo "WARN: sshd failed to start"
  EOF
