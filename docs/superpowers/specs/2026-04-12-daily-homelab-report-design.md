# Daily Homelab Health Report — Design Spec

## Overview

An n8n workflow that runs daily at 7 AM ET, collects health data from the Docker host (via SSH) and K3s cluster (via in-cluster API), sends the combined data to Ollama for AI-powered summarization with recommendations, and posts the report to Discord.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│ n8n Workflow (K3s, cron 7 AM ET daily)                  │
│                                                          │
│  ┌──────────┐    ┌──────────────┐    ┌───────────────┐  │
│  │ SSH Node │───►│ Merge & Prep │───►│ Try Ollama    │  │
│  │(Docker   │    │  (combine    │    │   ├─ success ──┼──► Discord
│  │ host)    │    │   all data)  │    │   └─ fail     │  │
│  └──────────┘    └──────────────┘    │     ├─ Claude │  │
│  ┌──────────┐          ▲             │     └─ raw    │  │
│  │ K3s API  │──────────┘             └───────────────┘  │
│  │(HTTP Req)│                                           │
│  └──────────┘                                           │
└─────────────────────────────────────────────────────────┘
```

## Trigger

- **Type:** Cron
- **Schedule:** Daily at 7:00 AM America/New_York
- n8n already has `GENERIC_TIMEZONE=America/New_York` configured

## Data Collection

### SSH Node — Docker Host

A single SSH call to the Docker host (`100.123.171.3`, user `jmendoza`) runs a bash script that outputs one JSON object with three sections:

#### 1. HTTP Health Checks

Curl each Docker service endpoint with a 5-second timeout, capture the HTTP status code:

| Service | URL | Healthy |
|---------|-----|---------|
| dozzle | http://localhost:8080 | 2xx/3xx |
| paperless | http://localhost:8001/api/ | 2xx/3xx |
| paperless-ai | http://localhost:8002 | 2xx/3xx |
| paperless-gpt | http://localhost:8003 | 2xx/3xx |
| open-webui | http://localhost:3000 | 2xx/3xx |
| ollama | http://localhost:11434/api/tags | 2xx/3xx |
| open-notebook | http://localhost:8502 | 2xx/3xx |
| surrealdb | http://localhost:8000/health | 2xx/3xx |
| calibre | http://localhost:8084 | 2xx/3xx |
| calibre-web | http://localhost:8083 | 2xx/3xx |
| homeassistant | http://localhost:8123 | 2xx/3xx |
| plex | http://localhost:32400/identity | 2xx/3xx |
| homepage | http://localhost:3001 | 2xx/3xx |

Note: zigbee2mqtt is excluded (port 8090 is not exposed, runs on a different network).

#### 2. Container Status

```bash
docker compose ps --format json
```

Captures for each container:
- Name
- State (running/exited/restarting)
- Health status (healthy/unhealthy/none)
- Uptime (RunningFor)
- Restart count (from `docker inspect`)

#### 3. Disk Usage

```bash
df -h / /mnt/synology --output=source,size,used,avail,pcent
```

#### SSH Script Output Format

```json
{
  "http_checks": [
    {"service": "paperless", "url": "http://localhost:8001/api/", "status_code": 302, "healthy": true},
    ...
  ],
  "containers": [
    {"name": "paperless", "state": "running", "health": "healthy", "uptime": "9 days", "restarts": 0},
    ...
  ],
  "disk": [
    {"filesystem": "/dev/sda1", "size": "500G", "used": "200G", "available": "280G", "percent": "42%"},
    {"filesystem": "synology:/volume1/data", "size": "4T", "used": "2.8T", "available": "1.2T", "percent": "70%"}
  ]
}
```

### K3s API — HTTP Request Nodes (Parallel)

n8n runs in-cluster and has a service account token at `/var/run/secrets/kubernetes.io/serviceaccount/token`. Three parallel HTTP Request nodes:

#### 1. Node Status

```
GET https://kubernetes.default.svc/api/v1/nodes
Authorization: Bearer <service-account-token>
```

Extract: node name, status (Ready/NotReady), age, version.

Expected nodes:
- k3s-cp-01 (192.168.68.80)
- k3s-node-01 (192.168.68.84)
- k3s-node-02 (192.168.68.87)
- k3s-node-03 (192.168.68.89)

#### 2. Unhealthy Pods

```
GET https://kubernetes.default.svc/api/v1/pods?fieldSelector=status.phase!=Running,status.phase!=Succeeded
Authorization: Bearer <service-account-token>
```

Extract: pod name, namespace, phase, reason.

Note: n8n's service account needs cluster-wide read permissions. A ClusterRole with `get`/`list` on nodes, pods, and certificates is required.

#### 3. TLS Certificate Expiry

```
GET https://kubernetes.default.svc/apis/cert-manager.io/v1/certificates
Authorization: Bearer <service-account-token>
```

Extract: certificate name, namespace, ready status, notAfter date. Flag any cert expiring within 14 days.

Current certificates (20 total):
- docker-services namespace: 18 certs (all services)
- n8n namespace: 1 cert
- uptime-kuma namespace: 1 cert

## RBAC Requirements

n8n's service account needs a ClusterRole to read cluster-wide resources:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: n8n-health-reader
rules:
  - apiGroups: [""]
    resources: ["nodes", "pods"]
    verbs: ["get", "list"]
  - apiGroups: ["cert-manager.io"]
    resources: ["certificates"]
    verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: n8n-health-reader
subjects:
  - kind: ServiceAccount
    name: default
    namespace: n8n
roleRef:
  kind: ClusterRole
  name: n8n-health-reader
  apiGroup: rbac.authorization.k8s.io
```

## Data Merge

A Code node combines all collected data into a single JSON payload for the AI prompt:

```json
{
  "timestamp": "2026-04-12T07:00:00-04:00",
  "docker": { "http_checks": [...], "containers": [...], "disk": [...] },
  "k3s": { "nodes": [...], "unhealthy_pods": [...], "certificates": [...] }
}
```

## AI Summarization

### Primary: Ollama

- **Endpoint:** http://ollama.docker-services.svc.cluster.local/api/chat
- **Model:** Use the Ollama `chat` endpoint; the workflow sends `model: "llama3"` (can be changed in the node config)
- **Timeout:** 60 seconds

### Fallback: Claude API

- **Trigger:** Ollama HTTP request fails or times out
- **Endpoint:** https://api.anthropic.com/v1/messages
- **Model:** claude-sonnet-4-20250514
- **Credential:** Anthropic API key stored in n8n credentials

### Last Resort: Raw Data

- **Trigger:** Both Ollama and Claude fail
- **Action:** Format raw health data directly into a Discord embed, skip AI summary

### AI System Prompt

```
You are a homelab monitoring assistant. Analyze the health check data below and produce a concise daily report.

Format:
1. One-line overall status (e.g., "All systems healthy" or "2 issues detected")
2. Issues and warnings (if any), each with a brief explanation
3. Actionable recommendations (if any)

Flag these conditions:
- Services returning non-2xx/3xx HTTP status
- Containers in unhealthy/restarting state or with restart count > 3
- K3s nodes in NotReady state
- Pods in CrashLoopBackOff, Pending, or Error state
- TLS certificates expiring within 14 days
- Disk usage above 80%

Keep the report concise — this is a Discord message, not a document.
Do not repeat raw data. Summarize and explain.
```

## Discord Output

Post to the webhook via HTTP Request node.

### Message Format

Discord embed with:
- **Color:** Green (`#2ecc71`) if all healthy, Yellow (`#f1c40f`) if warnings, Red (`#e74c3c`) if critical issues
- **Title:** "Homelab Daily Report — {date}"
- **Description:** AI-generated summary
- **Footer:** "Powered by Ollama" or "Powered by Claude (Ollama was unreachable)" or "AI unavailable — raw data"

### Webhook

```
POST https://discord.com/api/webhooks/{webhook_id}/{webhook_token}
Content-Type: application/json

{
  "embeds": [{
    "title": "Homelab Daily Report — April 12, 2026",
    "description": "<AI summary here>",
    "color": 3066993,
    "footer": {"text": "Powered by Ollama | 7:00 AM ET"}
  }]
}
```

## Error Handling

| Failure | Behavior |
|---------|----------|
| SSH connection fails | K3s data still collected. Discord message flags "Docker host unreachable via SSH" |
| K3s API fails | Docker data still collected. Discord message flags "K3s API unreachable" |
| Ollama fails | Fall back to Claude API |
| Claude fails | Post raw structured data to Discord, no AI summary |
| Discord webhook fails | n8n retries once after 30 seconds. If still fails, workflow errors (logged in n8n) |

Principle: always deliver something to Discord, even if partial or degraded.

## n8n Credentials Required

| Credential | Type | Purpose |
|-----------|------|---------|
| Docker host SSH | SSH key or password | SSH into 100.123.171.3 to run health checks |
| Anthropic API key | HTTP Header Auth | Claude fallback for AI summarization |
| Discord webhook | URL (hardcoded in node) | Post report to Discord |

Ollama requires no credentials (accessed via internal K3s service DNS).

## Workflow Node Summary

1. **Cron Trigger** — 7 AM ET daily
2. **SSH Node** — Run health check script on Docker host
3. **HTTP Request: K3s Nodes** — GET /api/v1/nodes (parallel)
4. **HTTP Request: K3s Pods** — GET /api/v1/pods?fieldSelector=... (parallel)
5. **HTTP Request: K3s Certs** — GET /apis/cert-manager.io/v1/certificates (parallel)
6. **Code Node: Merge** — Combine all data into single JSON
7. **HTTP Request: Ollama** — Send to Ollama for summarization
8. **IF Node** — Check if Ollama succeeded
9. **HTTP Request: Claude** (fallback) — Send to Claude API if Ollama failed
10. **IF Node** — Check if Claude succeeded
11. **Code Node: Format Raw** (last resort) — Format raw data if both AI failed
12. **Code Node: Build Discord Embed** — Determine color, format message
13. **HTTP Request: Discord** — Post to webhook
