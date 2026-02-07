# Homelab Infrastructure

A hybrid infrastructure combining GPU-accelerated Docker services for AI workloads with a Kubernetes (K3s) cluster running on Raspberry Pi nodes.

## 🏗️ Architecture Overview

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

## 📦 Components

### Docker Services (GPU Host)
- **Ollama** - LLM runtime with GPU acceleration
- **Open-WebUI** - Chat interface for LLMs
- **Paperless-NGX** - Document management system
- **Paperless-GPT** - LLM-powered document processing
- **Paperless-AI** - RAG search and AI analysis
- **PostgreSQL** - Database for services
- **Redis** - Caching layer
- **Dozzle** - Container log viewer
- **Tika/Gotenberg** - Document processing

### K3s Cluster (Raspberry Pi)
- Lightweight Kubernetes distribution
- MetalLB for load balancing
- NFS storage provisioner
- n8n workflow automation (optional)
- Cert-manager for TLS certificates

## 🚀 Quick Start

### Prerequisites
- Docker & Docker Compose
- NVIDIA GPU with drivers (for AI services)
- Raspberry Pi 4 (4+ recommended for K3s nodes)
- NAS with NFS support (optional but recommended)
- Ansible (for K3s automation)

### 1. Clone and Configure

```bash
git clone <your-repo-url>
cd homelab

# Copy and configure environment files
cp paperless-ai/.env.example paperless-ai/.env
cp paperless-gpt/.env.example paperless-gpt/.env
# Edit .env files with your credentials
```

### 2. Start Docker Services

```bash
# Start all services
docker compose up -d

# Or start specific services
docker compose up -d ollama open-webui paperless
```

### 3. Deploy K3s Cluster

See [K3s Setup Guide](.github/k3s-guide.md) for detailed instructions.

```bash
cd raspberry-pi-setup/pi-k3s-ansible

# Configure inventory
cp inventory.ini.example inventory.ini
# Edit with your Pi IP addresses

# Deploy cluster
ansible-playbook site.yml
```

## 🔧 Configuration

### Docker Services

Service configuration is managed through:
- `docker-compose.yml` - Service definitions and orchestration
- `<service>/.env` - Environment-specific configuration
- Volume mounts for persistent data

**Key Directories:**
```
homelab/
├── docker-compose.yml          # Main orchestration
├── paperless/                  # Document storage
│   ├── consume/               # Document inbox
│   ├── data/                  # Database
│   └── media/                 # Processed documents
├── paperless-ai/
│   ├── .env                   # API tokens, config
│   └── data/                  # App state
├── ollama/
│   └── models/                # Downloaded LLM models
└── open-webui/
    └── data/                  # User data and settings
```

### K3s Cluster

Cluster configuration uses Ansible playbooks:
- `site.yml` - Main cluster installation
- `metalb.yml` - Load balancer setup
- `nfs-storage.yml` - NFS provisioner
- `inventory.ini` - Node definitions

## 🌐 Service URLs

| Service | URL | Purpose |
|---------|-----|---------|
| Dozzle | http://localhost:8080 | Container logs |
| Paperless | http://localhost:8001 | Document management |
| Paperless-AI | http://localhost:8002 | RAG search interface |
| Paperless-GPT | http://localhost:8003 | LLM processing |
| Open-WebUI | http://localhost:3000 | Chat interface |
| Ollama API | http://localhost:11434 | LLM runtime |

## 📚 Detailed Documentation

- **[Docker Stack Guide](.github/docker-guide.md)** - Detailed Docker Compose workflows
- **[K3s Cluster Guide](.github/k3s-guide.md)** - Ansible playbooks and Kubernetes operations
- **[AI Coding Agent Instructions](.github/copilot-instructions.md)** - Developer guide

## 🔐 Security Considerations

### Before Pushing to GitHub

1. **Never commit `.env` files** - Contains API tokens and credentials
2. **Use `.gitignore`** - Exclude sensitive files and data directories
3. **Use placeholder values** - Replace real credentials in example files
4. **Review commits** - Check for accidentally committed secrets

### Recommended `.env` Structure

Create `.env.example` files with placeholders:
```bash
PAPERLESS_API_TOKEN=your_api_token_here
PAPERLESS_USERNAME=your_username_here
OLLAMA_HOST=http://ollama:11434
```

Users copy and customize:
```bash
cp paperless-ai/.env.example paperless-ai/.env
# Edit with real values
```

## 🛠️ Common Operations

### Docker

```bash
# View logs
docker compose logs --tail=200 <service>

# Restart service
docker compose restart <service>

# Update service
docker compose pull <service>
docker compose up -d <service>

# Debug container
docker exec -it <container> /bin/bash
```

### K3s

```bash
cd raspberry-pi-setup/pi-k3s-ansible

# Check cluster status
ansible all -m ping
export KUBECONFIG=~/.kube/k3s-config
kubectl get nodes

# Update MetalLB IP range
# Edit metallb.yml, then:
ansible-playbook metalb.yml

# Deploy workloads
kubectl apply -f k3s-manifests/
```

## 🐛 Troubleshooting

### Docker Issues

| Issue | Solution |
|-------|----------|
| Service loses config on restart | Add volume mount: `./service/data:/app/.data` |
| Can't reach service internally | Use container name: `http://ollama:11434` |
| GPU not detected | Check `nvidia-smi` and Docker GPU runtime |

### K3s Issues

| Issue | Solution |
|-------|----------|
| DNS resolution fails after reboot | Wait 30s for network, check `/etc/netplan/*.yaml` |
| K3s install fails | Enable cgroups in `/boot/firmware/cmdline.txt` |
| MetalLB no IPs | Update IP range to avoid DHCP conflicts |

## 📊 Storage Strategy

| Type | Path | Purpose | Backup |
|------|------|---------|--------|
| NAS volumes | `/mnt/synology/*` | AI models, databases | Automatic |
| Local config | `./service/data` | Service state | Git (examples) |
| Temporary | Container ephemeral | Logs, cache | None |

## 🤝 Contributing

This is a personal homelab setup, but feel free to:
- Report issues
- Suggest improvements
- Share your own configurations

## 📝 License

MIT License - Feel free to use and modify for your own homelab.

## 🙏 Acknowledgments

Built with:
- [Ollama](https://ollama.ai/) - LLM runtime
- [Open-WebUI](https://github.com/open-webui/open-webui) - Chat interface
- [Paperless-NGX](https://github.com/paperless-ngx/paperless-ngx) - Document management
- [K3s](https://k3s.io/) - Lightweight Kubernetes
- [Ansible](https://www.ansible.com/) - Automation platform

---

**Note**: This README assumes you've already sanitized sensitive data. See [Security Considerations](#-security-considerations) before pushing to GitHub.
