# Homelab AI Coding Agent Instructions

> **Quick Start**: Hybrid infrastructure with Docker Compose (AI services) + K3s cluster (Raspberry Pi)
> 
> 📖 **Detailed Guides**: [Docker Stack](docker-guide.md) | [K3s Cluster](k3s-guide.md)

## 🚀 Quick Reference

### Common Commands
```bash
# Docker services (from /home/jmendoza/homelab)
docker compose logs --tail=200 <service>
docker compose up -d <service>
docker compose restart <service>

# K3s cluster (from raspberry-pi-setup/pi-k3s-ansible)
ansible-playbook site.yml          # Full setup
ansible all -m ping                # Test connectivity
export KUBECONFIG=~/.kube/k3s-config && kubectl get nodes
```

### Service URLs
| Service | URL | Purpose |
|---------|-----|---------|
| Dozzle | http://localhost:8080 | Log viewer |
| Paperless | http://localhost:8001 | Document management |
| Paperless-AI | http://localhost:8002 | RAG search |
| Paperless-GPT | http://localhost:8003 | LLM processing |
| Open-WebUI | http://localhost:3000 | Chat interface |
| Ollama API | http://localhost:11434 | LLM runtime |

### Critical Patterns
- **Volume persistence**: If service loses config on restart → Add `./service/data:/app/.data` volume mount
- **Service refs**: Use container names (`http://ollama:11434`, not `localhost`)
- **Environment vars**: Use `env_file: ./service/.env` (never commit tokens)
- **Pi reboots**: Always wait for network + test DNS before proceeding

---

## 📋 Table of Contents

1. [Project Architecture](#project-architecture)
2. [Daily Development Workflows](#daily-development-workflows)
3. [Configuration Conventions](#configuration-conventions)
4. [Troubleshooting](#troubleshooting)
5. [File Organization](#file-organization)

---

## Project Architecture

### Infrastructure Overview
```
┌─────────────────────────────────────────────────────────────┐
│ GPU-Enabled Host (Docker Compose)                          │
│ ┌─────────┐  ┌──────────┐  ┌──────────────┐               │
│ │ Ollama  │→ │ Open-    │  │ Paperless    │               │
│ │ (GPU)   │  │ WebUI    │  │ Ecosystem    │               │
│ └─────────┘  └──────────┘  └──────────────┘               │
└─────────────────────────────────────────────────────────────┘
                                ↕
┌─────────────────────────────────────────────────────────────┐
│ K3s Cluster (Raspberry Pi)                                  │
│ ┌──────────────┐  ┌────────┐  ┌────────┐  ┌────────┐      │
│ │ k3s-cp-01    │  │ node-01│  │ node-02│  │ node-03│      │
│ │ (control)    │  │        │  │        │  │        │      │
│ └──────────────┘  └────────┘  └────────┘  └────────┘      │
└─────────────────────────────────────────────────────────────┘
```

### Storage Strategy
| Type | Path | Purpose | Backup |
|------|------|---------|--------|
| NAS volumes | `/mnt/synology/*` | AI models, databases, documents | Auto |
| Local config | `./service/data` | Service state that must persist | Git-tracked |
| Temporary | Container ephemeral | Logs, cache | None |

**Key Pattern**: Service loses config on restart? → Missing volume mount (e.g., `./paperless-ai/data:/app/.data`)

### Service Communication Flow
```
Document Upload → Paperless → Paperless-GPT → Ollama (LLM)
                           ↓
                    Paperless-AI ← Ollama (embedding)
                           ↓
                    Vector DB Search
```

**Internal refs**: Always use container names (`http://paperless:8000`, `http://ollama:11434`)

---

## Daily Development Workflows

### Docker Stack Operations

**When to use**: Managing AI services, paperless ecosystem, or debugging containers

See [Docker Guide](docker-guide.md) for detailed Docker Compose workflows.

**Quick patterns**:
- Restart after config change: `docker compose up -d <service>`
- View recent logs: `docker compose logs --tail=200 <service>`
- Interactive debug: `docker exec -it <container> /bin/bash`

### K3s Cluster Operations

**When to use**: Managing Raspberry Pi cluster, deploying workloads, or configuring networking

See [K3s Guide](k3s-guide.md) for detailed Ansible and Kubernetes workflows.

**Quick decision tree**:
```
New cluster? → setup-ssh-keys.yml → site.yml → metalb.yml
Need to update IP range? → Edit metalb.yml → ansible-playbook metalb.yml
Cluster issues? → ansible all -m ping → Check DNS → Review cgroups
```

---

## Configuration Conventions

### Docker Compose Services
When adding a new service, follow this checklist:

1. ✅ Group with comment header (`# ---------------------------`)
2. ✅ Use `env_file: ./service/.env` (not inline `environment` unless service-specific)
3. ✅ Add volume mount for persistent data if stateful
4. ✅ Set `restart: unless-stopped` for production services
5. ✅ Use `depends_on` to document service relationships

**Example** (from [docker-compose.yml](../docker-compose.yml#L147-L162)):
```yaml
# ---------------------------
# Service Name
# ---------------------------
service-name:
  image: org/service:latest
  container_name: service-name
  ports:
    - "8080:8080"
  env_file:
    - ./service-name/.env
  volumes:
    - /mnt/synology/data:/app/data
    - ./service-name/data:/app/.config
  depends_on:
    - dependency-service
  restart: unless-stopped
```

### Ansible Playbook Patterns
When modifying playbooks, follow these conventions:

- ✅ Use `creates:` on shell commands for idempotency
- ✅ Add `changed_when` for commands that always show "changed"
- ✅ Include `retries` + `delay` for network-dependent tasks
- ✅ Test DNS before downloads (`nslookup get.k3s.io`)
- ✅ Use `delegate_to: localhost` + `become: false` for local file operations
- ✅ Add `wait_for` after reboots (network needs ~30s to stabilize)

---

## Troubleshooting

### Common Error Patterns

| Error Signature | Root Cause | Solution |
|----------------|------------|----------|
| `Could not resolve host` after reboot | DNS not configured | Add `nameservers: {addresses: ['8.8.8.8']}` to netplan + `wait_for` task |
| Service loses config on restart | Missing volume mount | Add `./service/data:/app/.data` to volumes |
| `K3s install fails` | Memory cgroups not enabled | Append to `/boot/firmware/cmdline.txt`: `cgroup_memory=1 cgroup_enable=memory` |
| `MetalLB no IPs assigned` | IP range conflicts with DHCP | Update `metallb_ip_range` in metalb.yml to non-DHCP range |

### Debug Commands
```bash
# Docker service investigation
docker compose logs --tail=200 <service>
docker inspect <container>
docker exec -it <container> /bin/bash

# K3s cluster investigation
ansible all -m ping
ansible k3s_server -m shell -a "k3s kubectl get nodes -o wide" -b
ansible k3s_agents -m shell -a "journalctl -u k3s-agent -n 50" -b

# Network debugging (on Pis)
ansible pis -m shell -a "cat /boot/firmware/cmdline.txt" -b  # Check cgroups
ansible pis -m shell -a "cat /etc/netplan/*.yaml" -b         # Check network config
ansible pis -m shell -a "nslookup google.com" -b             # Test DNS
```

---

## File Organization

```
homelab/
├── .github/
│   ├── copilot-instructions.md    # This file (main guide)
│   ├── docker-guide.md            # Detailed Docker stack info
│   └── k3s-guide.md               # Detailed K3s cluster info
│
├── docker-compose.yml             # Main service orchestration
│
├── <service>/                     # Per-service directories
│   ├── .env                       # Config (gitignored, user-specific)
│   ├── data/                      # Persistent local data
│   └── prompts/                   # Service-specific templates
│
└── raspberry-pi-setup/
    ├── bootstrap-pis.sh           # Legacy manual setup (replaced by Ansible)
    └── pi-k3s-ansible/
        ├── site.yml               # Main cluster install
        ├── metalb.yml             # Load balancer addon
        ├── setup-ssh-keys.yml     # SSH key deployment
        ├── inventory.ini          # Host definitions
        └── README.md              # Detailed usage guide
```

### Key Files Reference
- [docker-compose.yml](../docker-compose.yml) - All Docker services, volumes, networks
- [inventory.ini](../raspberry-pi-setup/pi-k3s-ansible/inventory.ini) - Pi node IPs and groups
- [site.yml](../raspberry-pi-setup/pi-k3s-ansible/site.yml) - K3s installation playbook
- [metalb.yml](../raspberry-pi-setup/pi-k3s-ansible/metalb.yml) - Load balancer config
