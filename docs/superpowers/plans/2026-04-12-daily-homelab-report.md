# Daily Homelab Health Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an n8n workflow that runs daily at 7 AM ET, collects Docker + K3s health data, summarizes with Ollama (Claude fallback), and posts to Discord.

**Architecture:** SSH into the Docker host for container/HTTP/disk checks, hit the K3s API from within the cluster for node/pod/cert status, merge all data, send to Ollama for AI summarization with Claude as fallback, and post a color-coded embed to Discord.

**Tech Stack:** n8n (workflow automation), K3s API, SSH, Ollama API, Anthropic API, Discord webhooks

---

### Task 1: Create RBAC for n8n K3s API Access

n8n's default service account in the `n8n` namespace has no cluster-wide permissions. We need a ClusterRole and ClusterRoleBinding so the workflow can read nodes, pods, and cert-manager certificates.

**Files:**
- Create: `k3s-manifests/n8n/n8n-health-rbac.yaml`

- [ ] **Step 1: Create the RBAC manifest**

```yaml
# k3s-manifests/n8n/n8n-health-rbac.yaml
---
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

- [ ] **Step 2: Apply the RBAC manifest**

Run:
```bash
export KUBECONFIG=~/.kube/k3s-config
kubectl apply -f k3s-manifests/n8n/n8n-health-rbac.yaml
```

Expected:
```
clusterrole.rbac.authorization.k8s.io/n8n-health-reader created
clusterrolebinding.rbac.authorization.k8s.io/n8n-health-reader created
```

- [ ] **Step 3: Verify n8n can access the K3s API**

Run from inside the n8n pod to confirm the service account can read nodes:
```bash
export KUBECONFIG=~/.kube/k3s-config
kubectl exec -n n8n deployment/n8n -- sh -c '
  TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
  curl -sk -H "Authorization: Bearer $TOKEN" \
    https://kubernetes.default.svc/api/v1/nodes | head -c 200
'
```

Expected: JSON output starting with `{"kind":"NodeList"...` (not a 403 Forbidden).

- [ ] **Step 4: Commit**

```bash
git add k3s-manifests/n8n/n8n-health-rbac.yaml
git commit -m "feat: add RBAC for n8n health report K3s API access"
```

---

### Task 2: Create the SSH Health Check Script

This script runs on the Docker host via n8n's SSH node. It collects HTTP health checks, container status, and disk usage, then outputs structured JSON.

**Files:**
- Create: `scripts/homelab-health-check.sh`

- [ ] **Step 1: Create the health check script**

```bash
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
containers="["
first=true
while IFS= read -r line; do
  name=$(echo "$line" | jq -r '.Name')
  state=$(echo "$line" | jq -r '.State')
  health=$(echo "$line" | jq -r '.Health')
  running_for=$(echo "$line" | jq -r '.RunningFor')
  # Get restart count from docker inspect
  restarts=$(docker inspect --format '{{.RestartCount}}' "$name" 2>/dev/null || echo "0")
  if [ "$first" = true ]; then first=false; else containers+=","; fi
  containers+="{\"name\":\"$name\",\"state\":\"$state\",\"health\":\"$health\",\"uptime\":\"$running_for\",\"restarts\":$restarts}"
done < <(docker compose ps --format json 2>/dev/null)
containers+="]"

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
```

- [ ] **Step 2: Make the script executable and test locally**

Run:
```bash
chmod +x scripts/homelab-health-check.sh
bash scripts/homelab-health-check.sh | jq .
```

Expected: Valid JSON with `http_checks`, `containers`, and `disk` arrays populated with real data.

- [ ] **Step 3: Commit**

```bash
git add scripts/homelab-health-check.sh
git commit -m "feat: add SSH health check script for n8n daily report"
```

---

### Task 3: Set Up SSH Key for n8n

n8n needs passwordless SSH access to the Docker host. This is a manual step — generate a key pair and configure the n8n credential in the UI.

- [ ] **Step 1: Generate an SSH key pair for n8n**

Run on the Docker host:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/n8n_health_check -N "" -C "n8n-health-report"
```

- [ ] **Step 2: Add the public key to authorized_keys**

Run:
```bash
cat ~/.ssh/n8n_health_check.pub >> ~/.ssh/authorized_keys
```

- [ ] **Step 3: Test SSH locally**

Run:
```bash
ssh -i ~/.ssh/n8n_health_check -o StrictHostKeyChecking=no jmendoza@100.123.171.3 'echo ok'
```

Expected: `ok`

- [ ] **Step 4: Create the SSH credential in n8n**

Open n8n at `https://n8n.justinmendoza.net`:
1. Go to **Settings → Credentials → Add Credential**
2. Search for **SSH**
3. Fill in:
   - **Host:** `100.123.171.3`
   - **Port:** `22`
   - **Username:** `jmendoza`
   - **Authentication:** Private Key
   - **Private Key:** paste contents of `~/.ssh/n8n_health_check`
4. Save as "Docker Host SSH"

- [ ] **Step 5: Create the Anthropic API credential in n8n**

1. Go to **Settings → Credentials → Add Credential**
2. Search for **Header Auth**
3. Fill in:
   - **Name:** `x-api-key`
   - **Value:** your Anthropic API key
4. Save as "Anthropic API Key"

---

### Task 4: Create the n8n Workflow JSON

This is the complete workflow that can be imported into n8n. It wires together all the nodes: cron trigger, SSH data collection, K3s API calls, merge, Ollama/Claude AI summarization with fallback, and Discord posting.

**Files:**
- Create: `n8n-workflows/daily-homelab-report.json`

- [ ] **Step 1: Create the workflow JSON**

```json
{
  "name": "Daily Homelab Health Report",
  "nodes": [
    {
      "parameters": {
        "rule": {
          "interval": [
            {
              "triggerAtHour": 7,
              "triggerAtMinute": 0
            }
          ]
        }
      },
      "id": "trigger",
      "name": "Daily 7AM Trigger",
      "type": "n8n-nodes-base.scheduleTrigger",
      "typeVersion": 1.2,
      "position": [0, 0]
    },
    {
      "parameters": {
        "command": "bash /home/jmendoza/homelab/scripts/homelab-health-check.sh",
        "cwd": "/home/jmendoza/homelab"
      },
      "id": "ssh_docker",
      "name": "SSH Docker Health",
      "type": "n8n-nodes-base.ssh",
      "typeVersion": 1,
      "position": [250, -100],
      "credentials": {
        "sshPassword": {
          "id": "",
          "name": "Docker Host SSH"
        }
      },
      "onError": "continueRegularOutput"
    },
    {
      "parameters": {
        "url": "https://kubernetes.default.svc/api/v1/nodes",
        "authentication": "genericCredentialType",
        "genericAuthType": "none",
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "Authorization",
              "value": "={{ 'Bearer ' + $('Read SA Token').item.json.token }}"
            }
          ]
        },
        "options": {
          "allowUnauthorizedCerts": true,
          "timeout": 10000
        }
      },
      "id": "k3s_nodes",
      "name": "K3s Get Nodes",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 4.2,
      "position": [500, -200],
      "onError": "continueRegularOutput"
    },
    {
      "parameters": {
        "url": "https://kubernetes.default.svc/api/v1/pods",
        "authentication": "genericCredentialType",
        "genericAuthType": "none",
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "Authorization",
              "value": "={{ 'Bearer ' + $('Read SA Token').item.json.token }}"
            }
          ]
        },
        "sendQuery": true,
        "queryParameters": {
          "parameters": [
            {
              "name": "fieldSelector",
              "value": "status.phase!=Running,status.phase!=Succeeded"
            }
          ]
        },
        "options": {
          "allowUnauthorizedCerts": true,
          "timeout": 10000
        }
      },
      "id": "k3s_pods",
      "name": "K3s Unhealthy Pods",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 4.2,
      "position": [500, 0],
      "onError": "continueRegularOutput"
    },
    {
      "parameters": {
        "url": "https://kubernetes.default.svc/apis/cert-manager.io/v1/certificates",
        "authentication": "genericCredentialType",
        "genericAuthType": "none",
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "Authorization",
              "value": "={{ 'Bearer ' + $('Read SA Token').item.json.token }}"
            }
          ]
        },
        "options": {
          "allowUnauthorizedCerts": true,
          "timeout": 10000
        }
      },
      "id": "k3s_certs",
      "name": "K3s TLS Certs",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 4.2,
      "position": [500, 200],
      "onError": "continueRegularOutput"
    },
    {
      "parameters": {
        "jsCode": "// Read the service account token from the filesystem\nconst { execSync } = require('child_process');\ntry {\n  const token = execSync('cat /var/run/secrets/kubernetes.io/serviceaccount/token').toString().trim();\n  return [{ json: { token } }];\n} catch (e) {\n  return [{ json: { token: '', error: 'Could not read SA token' } }];\n}"
      },
      "id": "read_sa_token",
      "name": "Read SA Token",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [250, 100]
    },
    {
      "parameters": {
        "jsCode": "// Merge Docker SSH data + K3s API data into one payload\nconst timestamp = new Date().toISOString();\n\n// Docker data from SSH node\nlet docker = { http_checks: [], containers: [], disk: [] };\ntry {\n  const sshOutput = $('SSH Docker Health').first().json;\n  if (sshOutput.stdout) {\n    docker = JSON.parse(sshOutput.stdout);\n  }\n} catch (e) {\n  docker.error = 'SSH collection failed: ' + e.message;\n}\n\n// K3s nodes\nlet nodes = [];\ntry {\n  const nodesData = $('K3s Get Nodes').first().json;\n  if (nodesData.items) {\n    nodes = nodesData.items.map(n => ({\n      name: n.metadata.name,\n      status: n.status.conditions.find(c => c.type === 'Ready')?.status === 'True' ? 'Ready' : 'NotReady',\n      ip: n.status.addresses.find(a => a.type === 'InternalIP')?.address || 'unknown',\n      version: n.status.nodeInfo.kubeletVersion\n    }));\n  }\n} catch (e) {\n  nodes = [{ error: 'K3s nodes query failed: ' + e.message }];\n}\n\n// K3s unhealthy pods\nlet unhealthyPods = [];\ntry {\n  const podsData = $('K3s Unhealthy Pods').first().json;\n  if (podsData.items) {\n    unhealthyPods = podsData.items.map(p => ({\n      name: p.metadata.name,\n      namespace: p.metadata.namespace,\n      phase: p.status.phase,\n      reason: p.status.reason || 'unknown'\n    }));\n  }\n} catch (e) {\n  unhealthyPods = [{ error: 'K3s pods query failed: ' + e.message }];\n}\n\n// K3s certificates\nlet certificates = [];\ntry {\n  const certsData = $('K3s TLS Certs').first().json;\n  if (certsData.items) {\n    const now = new Date();\n    const fourteenDays = 14 * 24 * 60 * 60 * 1000;\n    certificates = certsData.items.map(c => {\n      const notAfter = c.status?.notAfter ? new Date(c.status.notAfter) : null;\n      const daysUntilExpiry = notAfter ? Math.floor((notAfter - now) / (24 * 60 * 60 * 1000)) : null;\n      return {\n        name: c.metadata.name,\n        namespace: c.metadata.namespace,\n        ready: c.status?.conditions?.find(cond => cond.type === 'Ready')?.status === 'True',\n        notAfter: c.status?.notAfter || 'unknown',\n        daysUntilExpiry,\n        expiringSoon: daysUntilExpiry !== null && daysUntilExpiry <= 14\n      };\n    });\n  }\n} catch (e) {\n  certificates = [{ error: 'K3s certs query failed: ' + e.message }];\n}\n\nreturn [{\n  json: {\n    timestamp,\n    docker,\n    k3s: { nodes, unhealthy_pods: unhealthyPods, certificates }\n  }\n}];"
      },
      "id": "merge_data",
      "name": "Merge All Data",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [750, 0]
    },
    {
      "parameters": {
        "url": "http://ollama.docker-services.svc.cluster.local/api/chat",
        "method": "POST",
        "sendBody": true,
        "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify({ model: 'llama3', messages: [{ role: 'system', content: 'You are a homelab monitoring assistant. Analyze the health check data below and produce a concise daily report.\\n\\nFormat:\\n1. One-line overall status (e.g., \"All systems healthy\" or \"2 issues detected\")\\n2. Issues and warnings (if any), each with a brief explanation\\n3. Actionable recommendations (if any)\\n\\nFlag these conditions:\\n- Services returning non-2xx/3xx HTTP status\\n- Containers in unhealthy/restarting state or with restart count > 3\\n- K3s nodes in NotReady state\\n- Pods in CrashLoopBackOff, Pending, or Error state\\n- TLS certificates expiring within 14 days\\n- Disk usage above 80%\\n\\nKeep the report concise — this is a Discord message, not a document.\\nDo not repeat raw data. Summarize and explain.' }, { role: 'user', content: JSON.stringify($json) }], stream: false }) }}",
        "options": {
          "timeout": 60000
        }
      },
      "id": "ollama_request",
      "name": "Ollama Summarize",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 4.2,
      "position": [1000, -100],
      "onError": "continueRegularOutput"
    },
    {
      "parameters": {
        "conditions": {
          "options": {
            "caseSensitive": true,
            "leftValue": "",
            "typeValidation": "strict"
          },
          "conditions": [
            {
              "id": "ollama-check",
              "leftValue": "={{ $json.message?.content }}",
              "rightValue": "",
              "operator": {
                "type": "string",
                "operation": "isNotEmpty"
              }
            }
          ],
          "combinator": "and"
        }
      },
      "id": "if_ollama_ok",
      "name": "Ollama OK?",
      "type": "n8n-nodes-base.if",
      "typeVersion": 2,
      "position": [1250, -100]
    },
    {
      "parameters": {
        "url": "https://api.anthropic.com/v1/messages",
        "method": "POST",
        "sendHeaders": true,
        "headerParameters": {
          "parameters": [
            {
              "name": "x-api-key",
              "value": "={{ $credentials.httpHeaderAuth.value }}"
            },
            {
              "name": "anthropic-version",
              "value": "2023-06-01"
            },
            {
              "name": "Content-Type",
              "value": "application/json"
            }
          ]
        },
        "sendBody": true,
        "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify({ model: 'claude-sonnet-4-20250514', max_tokens: 1024, system: 'You are a homelab monitoring assistant. Analyze the health check data below and produce a concise daily report.\\n\\nFormat:\\n1. One-line overall status (e.g., \"All systems healthy\" or \"2 issues detected\")\\n2. Issues and warnings (if any), each with a brief explanation\\n3. Actionable recommendations (if any)\\n\\nFlag these conditions:\\n- Services returning non-2xx/3xx HTTP status\\n- Containers in unhealthy/restarting state or with restart count > 3\\n- K3s nodes in NotReady state\\n- Pods in CrashLoopBackOff, Pending, or Error state\\n- TLS certificates expiring within 14 days\\n- Disk usage above 80%\\n\\nKeep the report concise — this is a Discord message, not a document.\\nDo not repeat raw data. Summarize and explain.', messages: [{ role: 'user', content: JSON.stringify($('Merge All Data').first().json) }] }) }}",
        "options": {
          "timeout": 30000
        }
      },
      "id": "claude_request",
      "name": "Claude Fallback",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 4.2,
      "position": [1500, 100],
      "credentials": {
        "httpHeaderAuth": {
          "id": "",
          "name": "Anthropic API Key"
        }
      },
      "onError": "continueRegularOutput"
    },
    {
      "parameters": {
        "conditions": {
          "options": {
            "caseSensitive": true,
            "leftValue": "",
            "typeValidation": "strict"
          },
          "conditions": [
            {
              "id": "claude-check",
              "leftValue": "={{ $json.content?.[0]?.text }}",
              "rightValue": "",
              "operator": {
                "type": "string",
                "operation": "isNotEmpty"
              }
            }
          ],
          "combinator": "and"
        }
      },
      "id": "if_claude_ok",
      "name": "Claude OK?",
      "type": "n8n-nodes-base.if",
      "typeVersion": 2,
      "position": [1750, 100]
    },
    {
      "parameters": {
        "jsCode": "// Last resort: format raw data when both AI services fail\nconst data = $('Merge All Data').first().json;\nlet lines = ['**AI summarization unavailable — raw data below**\\n'];\n\n// Docker HTTP checks\nif (data.docker?.http_checks) {\n  lines.push('**Docker Services:**');\n  for (const svc of data.docker.http_checks) {\n    const icon = svc.healthy ? '✅' : '❌';\n    lines.push(`${icon} ${svc.service}: HTTP ${svc.status_code}`);\n  }\n  lines.push('');\n}\n\n// Disk\nif (data.docker?.disk) {\n  lines.push('**Disk Usage:**');\n  for (const d of data.docker.disk) {\n    lines.push(`${d.filesystem}: ${d.percent} used (${d.used}/${d.size})`);\n  }\n  lines.push('');\n}\n\n// K3s nodes\nif (data.k3s?.nodes) {\n  lines.push('**K3s Nodes:**');\n  for (const n of data.k3s.nodes) {\n    const icon = n.status === 'Ready' ? '✅' : '❌';\n    lines.push(`${icon} ${n.name}: ${n.status}`);\n  }\n  lines.push('');\n}\n\n// Unhealthy pods\nif (data.k3s?.unhealthy_pods?.length > 0) {\n  lines.push('**Unhealthy Pods:**');\n  for (const p of data.k3s.unhealthy_pods) {\n    lines.push(`❌ ${p.namespace}/${p.name}: ${p.phase}`);\n  }\n}\n\nreturn [{ json: { summary: lines.join('\\n'), source: 'raw' } }];"
      },
      "id": "format_raw",
      "name": "Format Raw Data",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [2000, 300]
    },
    {
      "parameters": {
        "jsCode": "// Build the Discord embed with color coding\nlet summary = '';\nlet source = '';\n\n// Determine which AI source provided the summary\ntry {\n  // Check Ollama path\n  const ollamaOutput = $('Ollama OK?').first().json;\n  if (ollamaOutput.message?.content) {\n    summary = ollamaOutput.message.content;\n    source = 'Powered by Ollama';\n  }\n} catch (e) {}\n\nif (!summary) {\n  try {\n    // Check Claude path\n    const claudeOutput = $('Claude OK?').first().json;\n    if (claudeOutput.content?.[0]?.text) {\n      summary = claudeOutput.content[0].text;\n      source = 'Powered by Claude (Ollama was unreachable)';\n    }\n  } catch (e) {}\n}\n\nif (!summary) {\n  try {\n    // Raw data path\n    const rawOutput = $('Format Raw Data').first().json;\n    summary = rawOutput.summary;\n    source = 'AI unavailable — raw data';\n  } catch (e) {\n    summary = 'Health report failed: could not collect or summarize data.';\n    source = 'Error';\n  }\n}\n\n// Determine embed color based on content\nlet color = 3066993; // green\nconst lowerSummary = summary.toLowerCase();\nif (lowerSummary.includes('critical') || lowerSummary.includes('down') || lowerSummary.includes('unreachable') || lowerSummary.includes('❌')) {\n  color = 15158332; // red #e74c3c\n} else if (lowerSummary.includes('warning') || lowerSummary.includes('issue') || lowerSummary.includes('expiring') || lowerSummary.includes('above 80')) {\n  color = 15844367; // yellow #f1c40f\n}\n\n// Truncate if over Discord's 4096 char embed limit\nif (summary.length > 4000) {\n  summary = summary.substring(0, 3997) + '...';\n}\n\nconst now = new Date();\nconst dateStr = now.toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric', timeZone: 'America/New_York' });\nconst timeStr = now.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit', timeZone: 'America/New_York' });\n\nreturn [{\n  json: {\n    embeds: [{\n      title: `Homelab Daily Report — ${dateStr}`,\n      description: summary,\n      color: color,\n      footer: { text: `${source} | ${timeStr} ET` }\n    }]\n  }\n}];"
      },
      "id": "build_embed",
      "name": "Build Discord Embed",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [2250, 0]
    },
    {
      "parameters": {
        "url": "https://discord.com/api/webhooks/1492744590502137996/ltFBXfWc48olPXA3jdwKwecKcuuS_d_b2NATnUSJ5iSBcn9GmAL3kBfaisM0geOeEONI",
        "method": "POST",
        "sendBody": true,
        "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify($json) }}",
        "options": {
          "timeout": 10000
        }
      },
      "id": "discord_post",
      "name": "Post to Discord",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 4.2,
      "position": [2500, 0]
    },
    {
      "parameters": {
        "jsCode": "// Extract Ollama summary for the success path\nreturn [{ json: { message: { content: $json.message?.content || '' } } }];"
      },
      "id": "ollama_success",
      "name": "Ollama Success",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [1500, -300]
    },
    {
      "parameters": {
        "jsCode": "// Extract Claude summary for the success path\nreturn [{ json: { content: [{ text: $json.content?.[0]?.text || '' }] } }];"
      },
      "id": "claude_success",
      "name": "Claude Success",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [2000, 0]
    }
  ],
  "connections": {
    "Daily 7AM Trigger": {
      "main": [
        [
          { "node": "SSH Docker Health", "type": "main", "index": 0 },
          { "node": "Read SA Token", "type": "main", "index": 0 }
        ]
      ]
    },
    "Read SA Token": {
      "main": [
        [
          { "node": "K3s Get Nodes", "type": "main", "index": 0 },
          { "node": "K3s Unhealthy Pods", "type": "main", "index": 0 },
          { "node": "K3s TLS Certs", "type": "main", "index": 0 }
        ]
      ]
    },
    "SSH Docker Health": {
      "main": [
        [
          { "node": "Merge All Data", "type": "main", "index": 0 }
        ]
      ]
    },
    "K3s Get Nodes": {
      "main": [
        [
          { "node": "Merge All Data", "type": "main", "index": 0 }
        ]
      ]
    },
    "K3s Unhealthy Pods": {
      "main": [
        [
          { "node": "Merge All Data", "type": "main", "index": 0 }
        ]
      ]
    },
    "K3s TLS Certs": {
      "main": [
        [
          { "node": "Merge All Data", "type": "main", "index": 0 }
        ]
      ]
    },
    "Merge All Data": {
      "main": [
        [
          { "node": "Ollama Summarize", "type": "main", "index": 0 }
        ]
      ]
    },
    "Ollama Summarize": {
      "main": [
        [
          { "node": "Ollama OK?", "type": "main", "index": 0 }
        ]
      ]
    },
    "Ollama OK?": {
      "main": [
        [
          { "node": "Ollama Success", "type": "main", "index": 0 }
        ],
        [
          { "node": "Claude Fallback", "type": "main", "index": 0 }
        ]
      ]
    },
    "Ollama Success": {
      "main": [
        [
          { "node": "Build Discord Embed", "type": "main", "index": 0 }
        ]
      ]
    },
    "Claude Fallback": {
      "main": [
        [
          { "node": "Claude OK?", "type": "main", "index": 0 }
        ]
      ]
    },
    "Claude OK?": {
      "main": [
        [
          { "node": "Claude Success", "type": "main", "index": 0 }
        ],
        [
          { "node": "Format Raw Data", "type": "main", "index": 0 }
        ]
      ]
    },
    "Claude Success": {
      "main": [
        [
          { "node": "Build Discord Embed", "type": "main", "index": 0 }
        ]
      ]
    },
    "Format Raw Data": {
      "main": [
        [
          { "node": "Build Discord Embed", "type": "main", "index": 0 }
        ]
      ]
    },
    "Build Discord Embed": {
      "main": [
        [
          { "node": "Post to Discord", "type": "main", "index": 0 }
        ]
      ]
    }
  },
  "settings": {
    "executionOrder": "v1"
  }
}
```

- [ ] **Step 2: Commit the workflow JSON**

```bash
mkdir -p n8n-workflows
git add n8n-workflows/daily-homelab-report.json
git commit -m "feat: add n8n daily homelab health report workflow"
```

---

### Task 5: Import and Test the Workflow

This task is done entirely in the n8n UI.

- [ ] **Step 1: Import the workflow**

1. Open n8n at `https://n8n.justinmendoza.net`
2. Click **Add workflow → Import from file**
3. Select `n8n-workflows/daily-homelab-report.json`
4. The workflow should appear with all nodes connected

- [ ] **Step 2: Configure credentials on nodes**

1. Click **SSH Docker Health** node → select the "Docker Host SSH" credential created in Task 3
2. Click **Claude Fallback** node → select the "Anthropic API Key" credential created in Task 3
3. Save the workflow

- [ ] **Step 3: Test the SSH node**

1. Click on **SSH Docker Health** node
2. Click **Test step**
3. Expected: JSON output with `http_checks`, `containers`, and `disk` arrays

- [ ] **Step 4: Test the full workflow manually**

1. Click **Test workflow** (runs from the trigger)
2. Verify each node executes without errors:
   - SSH Docker Health: returns JSON with health data
   - Read SA Token: returns a token string
   - K3s Get Nodes: returns NodeList JSON
   - K3s Unhealthy Pods: returns PodList JSON
   - K3s TLS Certs: returns CertificateList JSON
   - Merge All Data: returns combined JSON payload
   - Ollama Summarize: returns AI-generated summary (or errors, triggering fallback)
   - Build Discord Embed: returns embed JSON with color and formatted message
   - Post to Discord: returns 204 No Content
3. Check your Discord channel — a health report embed should appear

- [ ] **Step 5: Activate the workflow**

1. Toggle the **Active** switch in the top-right of the workflow editor
2. The workflow will now run daily at 7 AM ET

- [ ] **Step 6: Verify the cron trigger**

In n8n, go to **Executions** tab. After 7 AM the next morning, verify:
- Execution completed successfully
- Discord received the daily report
