# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Hybrid homelab infrastructure — no application code, only infrastructure-as-code:
- **Docker Compose** on a GPU-enabled host for AI/LLM workloads
- **K3s (Kubernetes)** on a 4-node Raspberry Pi cluster for scalable workloads

Detailed guides: `.github/docker-guide.md` | `.github/k3s-guide.md`

---

## Architecture

```
GPU Host (Docker Compose)              K3s Cluster (Raspberry Pi 4)
┌────────────────────────────┐         ┌──────────────────────────────┐
│ Ollama (GPU) ──► Open-WebUI│         │ k3s-cp-01   192.168.68.80    │
│ Paperless ecosystem        │◄──────► │ k3s-node-01 192.168.68.84    │
│ Calibre, Home Assistant    │         │ k3s-node-02 192.168.68.87    │
│ Watchtower, Dozzle         │         │ k3s-node-03 192.168.68.89    │
└────────────────────────────┘         └──────────────────────────────┘
```

**Document processing pipeline**: Upload → Paperless → Paperless-GPT → Ollama (LLM tagging) → Paperless-AI (RAG/vector search)

**K3s → Docker bridge**: `k3s-manifests/docker-services.yaml` uses ExternalName services so K3s can route to Docker host services.

---

## Docker Services

| Service | Port | Purpose |
|---------|------|---------|
| Dozzle | 8080 | Container log viewer |
| Paperless | 8001 | Document management |
| Paperless-AI | 8002 | RAG search |
| Paperless-GPT | 8003 | LLM document tagging |
| Open-WebUI | 3000 | Chat UI for Ollama |
| Ollama API | 11434 | GPU-accelerated LLM runtime |
| Calibre | 8084 | Ebook manager desktop |
| Calibre-Web | 8083 | Ebook web UI |
| Home Assistant | 8123 | Smart home automation |
| Zigbee2MQTT | 8080 | Zigbee-to-MQTT bridge |

---

## Critical Patterns

### Service Communication
Always use **container names** for inter-service references — never `localhost`:
```
http://ollama:11434        ✓
http://localhost:11434     ✗ (only works from the host)
```

### Home Assistant Networking
HA uses `privileged: true` with standard port mapping (`8123:8123`). Other containers reach it at `http://homeassistant:8123`. HA reaches Ollama via `http://ollama:11434`.

### Watchtower Auto-Updates
Watchtower runs nightly at 3 AM and only updates containers with the opt-in label:
```yaml
labels:
  - "com.centurylinklabs.watchtower.enable=true"
```
All current services include this label. New services should add it to participate in auto-updates.

### Volume Mount Strategy
| Data type | Mount path | Rationale |
|-----------|-----------|-----------|
| Large/persistent (models, DBs, docs, books) | `/mnt/synology/<service>/` | NAS-backed, auto-backed-up |
| Small service config/state | `./service-name/data/` | Local, fast |

**If a service loses config on restart → it's missing a volume mount.**

### New Service Template
```yaml
# ---------------------------
# Service Name
# ---------------------------
service-name:
  image: org/image:tag
  container_name: service-name
  labels:
    - "com.centurylinklabs.watchtower.enable=true"
  ports:
    - "HOST_PORT:CONTAINER_PORT"
  env_file:
    - ./service-name/.env
  volumes:
    - /mnt/synology/data:/app/data          # Large data on NAS
    - ./service-name/data:/app/.config      # Small config locally
  depends_on:
    - dependency-service
  restart: unless-stopped
```

---

## Common Commands

```bash
# Docker (from /home/jmendoza/homelab)
docker compose up -d <service>
docker compose logs --tail=200 <service>
docker compose pull <service> && docker compose up -d <service>
docker exec -it <container> /bin/bash

# K3s (from raspberry-pi-setup/pi-k3s-ansible)
export KUBECONFIG=~/.kube/k3s-config
kubectl get nodes -o wide
kubectl apply -f k3s-manifests/
ansible all -m ping
ansible-playbook site.yml           # Full cluster install
ansible-playbook metalb.yml         # Update MetalLB config
ansible-playbook nfs-storage.yml    # Update NFS provisioner
```

---

## Storage

- NAS: `/mnt/synology/` — AI models, databases, documents, books (auto-backed-up)
- Local config: `./service-name/data/` — Small per-service state
- Gitignored: `.env` files, `/mnt/synology/**`, `raspberry-pi-setup/pi-k3s-ansible/inventory.ini`, `k3s-manifests/*-secret*`

---

## K3s Cluster

**Ansible user**: `ubuntu` (with `become: true`)
**Kubeconfig**: `~/.kube/k3s-config` (gitignored, fetch per machine)

Add-ons: Flannel (CNI), Traefik (ingress), MetalLB (L2 LB), NFS provisioner, cert-manager (Let's Encrypt + Cloudflare DNS-01)

**Ansible conventions:**
- Use `creates:` on shell commands for idempotency
- `changed_when: false` for commands that always report "changed"
- `retries` + `delay` for network-dependent tasks
- `wait_for` after Pi reboots — network needs ~30s to stabilize

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Service loses config on restart | Add volume mount `./service/data:/app/.data` |
| Can't reach service from another container | Use container name, not `localhost` |
| K3s install fails on Pi | Append `cgroup_memory=1 cgroup_enable=memory` to `/boot/firmware/cmdline.txt` |
| `Could not resolve host` after reboot | Check `/etc/netplan/*.yaml` for nameservers; add `wait_for` task |
| MetalLB assigns no IPs | Set `metallb_ip_range` to non-DHCP range in `metalb.yml` |
| Paperless permission errors on NAS | Set `USERMAP_UID=1000` / `USERMAP_GID=1000` |

```bash
# Quick health checks
curl http://localhost:11434/api/tags       # Ollama
curl http://localhost:8001/api/            # Paperless
```

### Zigbee USB Dongle (Sonoff Zigbee 3.0 V2)

Automated via `scripts/wsl-usb-zigbee.ps1` (Windows Scheduled Task at logon) and `scripts/wsl-boot.sh` (WSL boot via `wsl.conf`).

| Action | Command |
|--------|---------|
| Manual attach from WSL | `powershell.exe -Command "usbipd attach --wsl --hardware-id 10c4:ea60"` |
| Manual modprobe | `sudo modprobe cp210x` |
| Verify device | `ls /dev/ttyUSB0` |
| Verify zigbee2mqtt | `docker logs zigbee2mqtt --tail 5` |
