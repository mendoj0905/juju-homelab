# CLAUDE.md — AI Assistant Guide for juju-homelab

This file provides essential context for AI coding assistants (Claude, Copilot, etc.) working in this repository.

## Project Overview

A hybrid homelab infrastructure combining:
- **Docker Compose** on a GPU-enabled host for AI/LLM workloads
- **K3s (Kubernetes)** on a 4-node Raspberry Pi cluster for scalable workloads

No traditional application code (no npm, pip, Makefile, test suite). This repo is pure infrastructure-as-code: Docker Compose manifests, Kubernetes YAML, and Ansible playbooks.

---

## Repository Structure

```
juju-homelab/
├── CLAUDE.md                              # This file
├── README.md                              # Human-facing project overview
├── docker-compose.yml                     # All Docker services (GPU host)
├── .gitignore                             # Excludes .env files, data dirs, kubeconfigs
│
├── .github/
│   ├── copilot-instructions.md            # AI agent quick reference
│   ├── docker-guide.md                    # Detailed Docker operations guide
│   └── k3s-guide.md                       # Detailed K3s/Ansible operations guide
│
├── k3s-manifests/                         # Kubernetes manifests for K3s cluster
│   ├── docker-services.yaml               # ExternalName services pointing to Docker host
│   ├── ingress-routes.yaml                # HTTP Traefik ingress
│   ├── ingress-routes-https.yaml          # HTTPS Traefik ingress (cert-manager)
│   ├── cert-manager-setup.yaml            # Let's Encrypt + Cloudflare DNS-01
│   ├── HTTPS_SETUP.md                     # TLS configuration guide
│   ├── n8n/                               # n8n workflow automation (optional)
│   └── nfs-provisioner/                   # NFS dynamic storage provisioner
│
├── paperless-ai/
│   └── .env.example                       # Config template for RAG search service
│
├── paperless-gpt/
│   ├── .env.example                       # Config template for LLM tagging service
│   └── prompts/                           # Go template files for LLM prompts
│       ├── tag_prompt.tmpl
│       ├── title_prompt.tmpl
│       ├── correspondent_prompt.tmpl
│       ├── document_type_prompt.tmpl
│       ├── created_date_prompt.tmpl
│       ├── custom_field_prompt.tmpl
│       ├── ocr_prompt.tmpl
│       └── adhoc-analysis_prompt.tmpl
│
└── raspberry-pi-setup/
    └── pi-k3s-ansible/
        ├── ansible.cfg                    # Pipelining enabled, timeout=30
        ├── inventory.ini                  # 4-node cluster (gitignored real IPs)
        ├── inventory.ini.example          # Template for inventory
        ├── site.yml                       # Main K3s installation playbook
        ├── metalb.yml                     # MetalLB load balancer setup
        ├── nfs-storage.yml                # NFS provisioner + client setup
        ├── setup-ssh-keys.yml             # SSH key deployment
        └── README.md                      # Ansible quick start guide
```

---

## Docker Services (docker-compose.yml)

All services run on the GPU-enabled host. The compose file uses comment headers (`# ---------------------------`) to group services.

### Service Inventory

| Container | Image | Port | Purpose |
|-----------|-------|------|---------|
| `ollama` | `ollama/ollama:latest` | 11434 | GPU-accelerated LLM runtime |
| `open-webui` | `ghcr.io/open-webui/open-webui:main` | 3000→8080 | Chat UI for LLMs |
| `openwebui-db` | `postgres:16` | — | PostgreSQL for Open-WebUI |
| `paperless` | `ghcr.io/paperless-ngx/paperless-ngx:latest` | 8001→8000 | Document management |
| `paperless-db` | `postgres:16` | — | PostgreSQL for Paperless |
| `paperless-redis` | `redis:7` | — | Redis cache for Paperless |
| `paperless-gpt` | `ghcr.io/icereed/paperless-gpt:latest` | 8003→8080 | LLM-powered document tagging |
| `paperless-ai` | `ghcr.io/clusterzx/paperless-ai:latest` | 8002→3000 | RAG search for documents |
| `gotenberg` | `docker.io/gotenberg/gotenberg:8.25` | — | PDF conversion |
| `tika` | `docker.io/apache/tika:latest` | — | Text extraction |
| `surrealdb` | `surrealdb/surrealdb:v2` | 8000 | Database for Open Notebook |
| `open-notebook` | `lfnovo/open_notebook:v1-latest-single` | 8502, 5055 | Research assistant with RAG |
| `calibre` | `lscr.io/linuxserver/calibre:latest` | 8084, 8085 | Full Calibre ebook manager |
| `calibre-web` | `lscr.io/linuxserver/calibre-web:latest` | 8083 | Lightweight ebook web UI |
| `dozzle` | `amir20/dozzle:latest` | 8080 | Container log viewer |

### Service URLs (localhost)

| Service | URL |
|---------|-----|
| Dozzle (logs) | http://localhost:8080 |
| Paperless | http://localhost:8001 |
| Paperless-AI | http://localhost:8002 |
| Paperless-GPT | http://localhost:8003 |
| Open-WebUI | http://localhost:3000 |
| Ollama API | http://localhost:11434 |
| Open Notebook UI | http://localhost:8502 |
| SurrealDB | http://localhost:8000 |
| Calibre Desktop | http://localhost:8084 |
| Calibre-Web | http://localhost:8083 |

---

## K3s Cluster (Raspberry Pi)

### Node Topology

| Role | Hostname | IP |
|------|----------|----|
| Control Plane | `k3s-cp-01` | 192.168.68.80 |
| Worker | `k3s-node-01` | 192.168.68.84 |
| Worker | `k3s-node-02` | 192.168.68.87 |
| Worker | `k3s-node-03` | 192.168.68.89 |

- Ansible user: `ubuntu` (with `become: true`)
- Kubeconfig saved to: `~/.kube/k3s-config` (gitignored)

### Cluster Add-ons

- **Flannel** — CNI (default K3s)
- **Traefik** — Ingress controller (default K3s)
- **MetalLB** — L2 load balancer for bare-metal IP allocation
- **NFS provisioner** — Dynamic PV provisioning from Synology NAS
- **cert-manager** — TLS automation via Let's Encrypt + Cloudflare DNS-01

### Kubernetes Namespaces

| Namespace | Purpose |
|-----------|---------|
| `docker-services` | ExternalName services bridging K3s → Docker host |
| `nfs-provisioner` | NFS storage provisioner |
| `cert-manager` | TLS certificate management |
| `n8n` | n8n workflow automation (optional) |

---

## Storage Strategy

| Type | Mount Path | Purpose | Backup |
|------|-----------|---------|--------|
| NAS-backed | `/mnt/synology/<service>/` | AI models, databases, documents | Automatic (NAS) |
| Local config | `./service/data/` | Service state (small, fast) | Git examples |
| Container ephemeral | (no mount) | Logs, cache | None |

**Rule:** If a service loses its configuration on restart, it needs a local volume mount (e.g., `./paperless-ai/data:/app/.data`).

---

## Configuration Conventions

### Environment Files

- **Never commit `.env` files** — they are gitignored and contain secrets
- **Always provide `.env.example`** with placeholder values
- Services reference env files via `env_file: ./service/.env`

```bash
# Setup pattern
cp paperless-ai/.env.example paperless-ai/.env
# Edit with real API tokens, credentials, etc.
```

### Docker Compose Service Pattern

When adding a new service, follow this template:

```yaml
# ---------------------------
# Service Name
# ---------------------------
service-name:
  image: org/image:tag
  container_name: service-name
  ports:
    - "HOST_PORT:CONTAINER_PORT"
  env_file:
    - ./service-name/.env
  volumes:
    - /mnt/synology/data:/app/data          # Large/persistent data on NAS
    - ./service-name/data:/app/.config      # Small config locally
  depends_on:
    - dependency-service
  restart: unless-stopped
```

Key rules:
- Use `env_file` (not inline `environment`) for secrets
- Set `restart: unless-stopped` on all production services
- Use `depends_on` for startup ordering and documentation
- Mount NAS paths for databases, AI models, and large files
- Mount local `./service/data/` for small service-specific state

### Service Communication

**Always use container names for internal references:**
```
http://ollama:11434        (not localhost:11434)
http://paperless:8000      (not localhost:8001)
redis://paperless-redis:6379
postgresql://paperless-db:5432/paperless
```

### Ansible Playbook Conventions

- Use `creates:` on shell commands to ensure idempotency
- Add `changed_when: false` for commands that always show "changed"
- Use `retries` + `delay` for network-dependent tasks
- Test DNS before downloads: `nslookup get.k3s.io`
- Use `delegate_to: localhost` + `become: false` for local file operations
- Always add `wait_for` after Pi reboots (network needs ~30s to stabilize)

---

## Development Workflows

### Managing Docker Services

```bash
# Start/restart all services
docker compose up -d

# Start/restart specific service
docker compose up -d <service-name>

# View logs (tail 200 lines)
docker compose logs --tail=200 <service-name>

# Shell into container for debugging
docker exec -it <container-name> /bin/bash

# Pull latest images and redeploy
docker compose pull <service-name>
docker compose up -d <service-name>

# Stop all services
docker compose down
```

### Managing K3s Cluster

```bash
# Set kubeconfig
export KUBECONFIG=~/.kube/k3s-config

# Check cluster state
kubectl get nodes -o wide
kubectl get pods -A

# Apply manifests
kubectl apply -f k3s-manifests/

# Ansible operations (from raspberry-pi-setup/pi-k3s-ansible)
ansible all -m ping                        # Test connectivity
ansible-playbook site.yml                  # Full cluster install
ansible-playbook metalb.yml               # Update MetalLB config
ansible-playbook nfs-storage.yml          # Update NFS provisioner
ansible-playbook setup-ssh-keys.yml       # Deploy SSH keys
```

### First-Time K3s Cluster Setup

```bash
cd raspberry-pi-setup/pi-k3s-ansible

# 1. Copy and configure inventory
cp inventory.ini.example inventory.ini
# Edit inventory.ini with actual Pi IP addresses

# 2. Deploy SSH keys (recommended)
ansible-playbook setup-ssh-keys.yml

# 3. Install K3s cluster
ansible-playbook site.yml

# 4. Install MetalLB load balancer
ansible-playbook metalb.yml

# 5. Install NFS storage provisioner
ansible-playbook nfs-storage.yml

# 6. Apply Kubernetes manifests
export KUBECONFIG=~/.kube/k3s-config
kubectl apply -f k3s-manifests/
```

---

## Troubleshooting

### Common Error Patterns

| Symptom | Root Cause | Fix |
|---------|-----------|-----|
| Service loses config on restart | Missing volume mount | Add `./service/data:/app/.data` to volumes |
| Can't reach service from another container | Using `localhost` instead of container name | Change to `http://service-name:port` |
| GPU not visible in Ollama | Docker GPU runtime not configured | Check `nvidia-smi` and Docker NVIDIA runtime |
| `Could not resolve host` after Pi reboot | DNS not stabilized | Add `wait_for` task + check `/etc/netplan/*.yaml` |
| K3s install fails on Pi | Memory cgroups disabled | Append to `/boot/firmware/cmdline.txt`: `cgroup_memory=1 cgroup_enable=memory` |
| MetalLB assigns no IPs | IP range conflicts with DHCP | Update `metallb_ip_range` in `metalb.yml` to a non-DHCP range |
| Paperless permission errors on NAS volumes | UID/GID mismatch | Set `USERMAP_UID=1000` and `USERMAP_GID=1000` in environment |

### Debug Commands

```bash
# Docker debugging
docker compose logs --tail=200 <service>
docker inspect <container>
docker exec -it <container> /bin/bash
docker stats                               # Resource usage

# K3s/Ansible debugging
ansible all -m ping
ansible k3s_server -m shell -a "k3s kubectl get nodes -o wide" -b
ansible k3s_agents -m shell -a "journalctl -u k3s-agent -n 50" -b

# Pi system checks
ansible pis -m shell -a "cat /boot/firmware/cmdline.txt" -b   # Check cgroups
ansible pis -m shell -a "cat /etc/netplan/*.yaml" -b          # Check network
ansible pis -m shell -a "nslookup google.com" -b              # Test DNS

# Health checks
curl http://localhost:11434/api/tags       # Ollama
curl http://localhost:8001/api/            # Paperless
curl http://localhost:3000/health          # Open-WebUI
curl http://localhost:8002/health          # Paperless-AI
```

---

## Security Conventions

1. **Never commit `.env` files** — gitignore covers `*.env` and `.env` at all levels
2. **Use `.env.example` templates** with placeholder values (e.g., `your_api_token_here`)
3. **Kubeconfig is gitignored** — `~/.kube/k3s-config` must be fetched fresh per machine
4. **Sensitive paths excluded from git:**
   - `*.env` / `.env`
   - `k3s-manifests/*-secret*`
   - `raspberry-pi-setup/pi-k3s-ansible/inventory.ini` (real IPs)
   - `/mnt/synology/**` (data directories)

---

## Paperless-GPT Prompt Templates

LLM prompt templates live in `paperless-gpt/prompts/` as Go template (`.tmpl`) files. These control how Ollama processes documents for metadata extraction.

| File | Purpose |
|------|---------|
| `tag_prompt.tmpl` | Suggest document tags |
| `title_prompt.tmpl` | Generate document title |
| `correspondent_prompt.tmpl` | Identify document sender/recipient |
| `document_type_prompt.tmpl` | Classify document type |
| `created_date_prompt.tmpl` | Extract document creation date |
| `custom_field_prompt.tmpl` | Extract custom metadata fields |
| `ocr_prompt.tmpl` | OCR improvement prompt |
| `adhoc-analysis_prompt.tmpl` | One-off document analysis |

Templates use standard Go `text/template` syntax. The paperless-gpt container mounts this directory at `/app/prompts`.

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Single source of truth for all Docker services |
| `raspberry-pi-setup/pi-k3s-ansible/site.yml` | Full K3s cluster installation |
| `raspberry-pi-setup/pi-k3s-ansible/inventory.ini` | Pi node IPs (gitignored, use `.example`) |
| `raspberry-pi-setup/pi-k3s-ansible/metalb.yml` | MetalLB IP range and config |
| `k3s-manifests/ingress-routes-https.yaml` | Traefik HTTPS ingress with TLS |
| `k3s-manifests/cert-manager-setup.yaml` | Let's Encrypt + Cloudflare cert config |
| `.github/docker-guide.md` | Deep-dive Docker operations guide |
| `.github/k3s-guide.md` | Deep-dive K3s and Ansible guide |
