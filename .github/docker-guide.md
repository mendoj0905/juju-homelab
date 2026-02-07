# Docker Compose Stack Guide

Detailed guide for managing AI services on the GPU-enabled host.

## Service Architecture

### AI/ML Stack
```
┌──────────────────────────────────────────────────────────┐
│                   Ollama (GPU)                           │
│              NVIDIA GPU Acceleration                     │
│           http://ollama:11434                            │
└─────────────────┬────────────────────────────────────────┘
                  │
         ┌────────┴─────────┐
         ↓                  ↓
┌─────────────────┐  ┌─────────────────┐
│  Open-WebUI     │  │ Paperless-GPT   │
│  (Chat UI)      │  │ (LLM Tagging)   │
│  :3000          │  │ :8003           │
└─────────────────┘  └────────┬────────┘
                              ↓
                     ┌────────────────┐
                     │  Paperless     │
                     │  (DMS)         │
                     │  :8001         │
                     └────────┬───────┘
                              ↓
                     ┌────────────────┐
                     │ Paperless-AI   │
                     │ (RAG Search)   │
                     │ :8002          │
                     └────────────────┘
```

### Supporting Services
- **PostgreSQL** (x2) - `paperless-db`, `openwebui-db`
- **Redis** - Queue for Paperless tasks
- **Gotenberg** - PDF conversion service
- **Tika** - Text extraction service
- **Dozzle** - Web-based log viewer

## Port Allocation

| Port | Service | Purpose |
|------|---------|---------|
| 3000 | open-webui | Chat interface for LLM interaction |
| 8001 | paperless | Document management system |
| 8002 | paperless-ai | RAG-powered document search |
| 8003 | paperless-gpt | Automated LLM document tagging |
| 8080 | dozzle | Real-time log viewer |
| 11434 | ollama | LLM API endpoint |

## Volume Strategy

### NAS-Backed Persistent Storage
Critical data stored on Synology NAS at `/mnt/synology/`:

```yaml
/mnt/synology/ai/
  ├── ollama/          # LLM models (large, ~10GB+ per model)
  ├── openwebui/       # Chat history, user data
  ├── openwebui-db/    # PostgreSQL database
  └── vectors/         # Paperless-AI vector embeddings

/mnt/synology/paperless/
  ├── db/              # PostgreSQL database
  ├── data/            # Document metadata
  ├── media/           # Uploaded documents
  ├── export/          # Document exports
  └── consume/         # Inbox for auto-import
```

### Local Configuration Storage
Version-controlled service configs at `./service-name/data`:

```yaml
./paperless-ai/data/    # App state (/app/.data in container)
./dozzle/data/          # User settings
./paperless-gpt/prompts/ # Custom LLM prompts
```

**Pattern**: If a service resets config on restart, add local volume mount.

## Common Operations

### Service Management

#### Start/Restart Services
```bash
# Restart single service after config change
docker compose up -d paperless-ai

# Restart with rebuild (after Dockerfile changes)
docker compose up -d --build <service>

# Restart multiple services
docker compose up -d paperless paperless-gpt ollama
```

#### Stop Services
```bash
# Stop single service
docker compose stop paperless-ai

# Stop all services
docker compose down

# Stop and remove volumes (DESTRUCTIVE)
docker compose down -v
```

#### View Status
```bash
# List running services
docker compose ps

# Show resource usage
docker stats

# Check service health
docker compose ps --format json | jq '.[].Health'
```

### Log Management

#### Using Dozzle (Recommended)
1. Open http://localhost:8080
2. Click service name
3. Live tail with search/filter

#### Using CLI
```bash
# Tail logs (last 200 lines)
docker compose logs --tail=200 paperless-ai

# Follow logs in real-time
docker compose logs -f paperless-gpt

# Filter by time
docker compose logs --since 30m ollama

# All services
docker compose logs --tail=100
```

### Debugging Services

#### Interactive Shell
```bash
# Access running container
docker exec -it paperless-ai /bin/bash

# Run one-off command
docker exec paperless-ai ls -la /app/.data

# Check environment variables
docker exec paperless-ai env
```

#### Inspect Configuration
```bash
# View full container config
docker inspect paperless-ai

# Check volume mounts
docker inspect paperless-ai | jq '.[0].Mounts'

# View environment variables
docker inspect paperless-ai | jq '.[0].Config.Env'
```

#### Network Debugging
```bash
# Test service connectivity from another container
docker exec paperless curl http://ollama:11434/api/tags

# Check DNS resolution
docker exec paperless nslookup paperless-gpt

# View network details
docker network inspect homelab_default
```

## Configuration Management

### Environment Files Pattern
Each service uses `./service/.env` for configuration:

```bash
homelab/
├── paperless-ai/.env       # API tokens, model settings
├── paperless-gpt/.env      # LLM provider config
├── dozzle/.env             # Auth settings
├── gotenberg/.env          # Conversion limits
└── tika/.env               # Extraction config
```

**Security**: Never commit `.env` files - they contain API tokens and passwords.

### Updating Service Configuration

1. **Edit `.env` file**:
   ```bash
   nano ./paperless-ai/.env
   # Update OLLAMA_MODEL=llama3.1:8b → llama3.2:8b
   ```

2. **Restart service**:
   ```bash
   docker compose up -d paperless-ai
   ```

3. **Verify change**:
   ```bash
   docker compose logs --tail=50 paperless-ai
   ```

### Adding New Services

Follow this template (from [docker-compose.yml](../docker-compose.yml)):

```yaml
# ---------------------------
# Service Name
# ---------------------------
my-service:
  image: org/service:latest
  container_name: my-service
  ports:
    - "8010:8080"
  env_file:
    - ./my-service/.env
  volumes:
    - /mnt/synology/my-service:/app/data  # Persistent data
    - ./my-service/config:/app/config     # Local config
  depends_on:
    - ollama                               # Service dependencies
  restart: unless-stopped
```

**Checklist**:
- ✅ Add comment header
- ✅ Use `env_file` for secrets
- ✅ Map to unique port
- ✅ Add volume mounts for persistence
- ✅ Set `restart: unless-stopped`
- ✅ Document in this guide

## Troubleshooting

### Service Won't Start

**Check logs**:
```bash
docker compose logs --tail=100 <service>
```

**Common causes**:
- Port already in use → Check `docker compose ps` or `lsof -i :PORT`
- Missing environment variable → Verify `.env` file exists
- Volume permission error → Check NAS mount permissions
- Dependency not ready → Increase `depends_on` wait time

### Service Loses Configuration

**Symptom**: Service config resets after `docker compose restart`

**Solution**: Add volume mount for config directory
```yaml
volumes:
  - ./service-name/data:/app/.data  # or /app/config, /root/.config, etc.
```

**Example**: paperless-ai fix ([docker-compose.yml](../docker-compose.yml#L157))

### Ollama Model Issues

**List available models**:
```bash
docker exec ollama ollama list
```

**Pull new model**:
```bash
docker exec ollama ollama pull llama3.2:8b
```

**Remove model**:
```bash
docker exec ollama ollama rm old-model:7b
```

**Check GPU usage**:
```bash
nvidia-smi  # On host
docker exec ollama nvidia-smi  # Inside container
```

### Paperless Ecosystem Issues

**Test Paperless API**:
```bash
docker exec paperless-gpt curl http://paperless:8000/api/
```

**Check Paperless-GPT LLM connection**:
```bash
docker exec paperless-gpt curl http://ollama:11434/api/tags
```

**Verify Paperless-AI embeddings**:
```bash
docker exec paperless-ai ls -lh /data/vectors
```

### Database Connection Errors

**PostgreSQL issues**:
```bash
# Check database is running
docker compose ps paperless-db

# View database logs
docker compose logs --tail=100 paperless-db

# Test connection from service
docker exec paperless pg_isready -h paperless-db
```

**Redis issues**:
```bash
# Check Redis
docker exec paperless-redis redis-cli ping
# Should return: PONG
```

## Performance Optimization

### GPU Memory Management

**Check VRAM usage**:
```bash
nvidia-smi --query-gpu=memory.used,memory.total --format=csv
```

**Reduce model memory** (edit service `.env`):
```bash
# paperless-gpt/.env
LLM_MODEL=llama3.1:8b  # Use 8B instead of 70B
OLLAMA_CONTEXT_LENGTH=4096  # Reduce from 8192
```

### Docker Cleanup

```bash
# Remove unused images
docker image prune -a

# Remove stopped containers
docker container prune

# Remove unused volumes (BE CAREFUL)
docker volume prune

# Remove build cache
docker builder prune
```

## Backup & Recovery

### Backup Critical Data

```bash
# Backup NAS volumes (on Synology NAS)
# Already handled by Synology backup tasks

# Backup local configs
tar -czf homelab-configs-$(date +%Y%m%d).tar.gz \
  paperless-ai/data \
  dozzle/data \
  paperless-gpt/prompts \
  docker-compose.yml \
  */​.env
```

### Restore Service

```bash
# Stop service
docker compose stop <service>

# Restore config
tar -xzf homelab-configs-20260131.tar.gz

# Restart service
docker compose up -d <service>
```

## Integration Patterns

### Service-to-Service Communication

Always use **container names** (not localhost):

```bash
# ✅ Correct
PAPERLESS_API_URL=http://paperless:8000
OLLAMA_HOST=http://ollama:11434

# ❌ Wrong
PAPERLESS_API_URL=http://localhost:8001
OLLAMA_HOST=http://localhost:11434
```

### External Access

Services are bound to `0.0.0.0` on host:
- From host: `http://localhost:8001`
- From network: `http://<host-ip>:8001`
- From other containers: `http://paperless:8000` (internal port)

## Quick Reference

### Essential Commands
```bash
# Daily operations
docker compose ps                          # Status
docker compose logs -f <service>           # Live logs
docker compose up -d <service>             # Restart
docker compose down && docker compose up -d  # Full restart

# Debugging
docker exec -it <container> /bin/bash      # Shell access
docker inspect <container>                 # Full config
docker stats                               # Resource usage

# Cleanup
docker system prune                        # Remove unused data
docker compose pull                        # Update images
```

### Service Health Checks
```bash
# Ollama
curl http://localhost:11434/api/tags

# Paperless
curl http://localhost:8001/api/

# Open-WebUI
curl http://localhost:3000/health

# Paperless-AI
curl http://localhost:8002/health
```
