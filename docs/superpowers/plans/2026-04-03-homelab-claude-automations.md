# Homelab Claude Automations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set up 2 hooks, 2 skills, 1 subagent, and 2 MCP servers to automate common homelab Claude Code workflows.

**Architecture:** All project-scoped config lives under `/home/jmendoza/homelab/.claude/`. Hooks go in `.claude/settings.local.json`. Skills go in `.claude/skills/<name>/SKILL.md`. Subagents go in `.claude/agents/<name>.md`. MCP servers go in project-root `.mcp.json`.

**Tech Stack:** Claude Code hooks (JSON stdin), Python 3 (YAML lint), Docker CLI, kubectl, npx, GitHub Personal Access Token.

---

## Task 1: Add Hooks to Project Settings

**Files:**
- Modify: `/home/jmendoza/homelab/.claude/settings.local.json`

The hooks JSON is added at the top level alongside `permissions`. Hooks receive tool input as JSON on stdin. Both hooks use `python3 -c` to parse stdin and act on `file_path`.

- [ ] **Step 1: Add hooks block to settings.local.json**

Replace the current contents of `/home/jmendoza/homelab/.claude/settings.local.json` with:

```json
{
  "permissions": {
    "allow": [
      "Bash(sudo modprobe:*)",
      "Read(//dev/**)",
      "Bash(export KUBECONFIG=~/.kube/k3s-config)",
      "Bash(kubectl get:*)",
      "Bash(kubectl describe:*)",
      "Bash(KUBECONFIG=~/.kube/k3s-config kubectl get pods -n kube-system -o wide 2>&1)",
      "Bash(KUBECONFIG=~/.kube/k3s-config kubectl describe node k3s-node-01)",
      "Bash(KUBECONFIG=~/.kube/k3s-config kubectl get pods --all-namespaces --field-selector spec.nodeName=k3s-node-01)",
      "Bash(KUBECONFIG=~/.kube/k3s-config kubectl get pods -A --field-selector spec.nodeName!=k3s-node-01)",
      "Bash(KUBECONFIG=~/.kube/k3s-config kubectl get pods -A 2>&1)",
      "Bash(KUBECONFIG=~/.kube/k3s-config kubectl get nodes -o wide 2>&1)",
      "Bash(KUBECONFIG=~/.kube/k3s-config kubectl get events --all-namespaces --sort-by='.lastTimestamp')",
      "Bash(ssh:*)",
      "Bash(KUBECONFIG=~/.kube/k3s-config kubectl get ingress -A)",
      "Bash(KUBECONFIG=~/.kube/k3s-config kubectl get svc -n kube-system)",
      "Bash(KUBECONFIG=~/.kube/k3s-config kubectl get pods -n kube-system)",
      "Bash(KUBECONFIG=~/.kube/k3s-config kubectl get svc -n docker-services)",
      "Bash(KUBECONFIG=~/.kube/k3s-config kubectl get endpoints -n docker-services)",
      "Bash(docker ps:*)",
      "Bash(ip addr:*)",
      "Bash(ping -c 2 100.123.171.3)",
      "Bash(KUBECONFIG=~/.kube/k3s-config kubectl get svc -n docker-services openwebui -o yaml)",
      "Bash(tailscale status:*)",
      "Read(//usr/bin/**)",
      "Read(//usr/sbin/**)",
      "Bash(systemctl status:*)",
      "Bash(curl -sv --connect-timeout 5 https://openwebui.justinmendoza.net)",
      "Bash(curl -sv --connect-timeout 5 -H \"Host: openwebui.justinmendoza.net\" http://192.168.68.200)",
      "Bash(curl:*)",
      "Bash(for svc:*)",
      "Bash(do echo:*)",
      "Bash(done)",
      "Bash(docker compose:*)",
      "Bash(wc -l /home/jmendoza/homelab/k3s-manifests/*.yaml /home/jmendoza/homelab/k3s-manifests/*/*.yaml)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "python3 -c \"\nimport sys, json\nd = json.load(sys.stdin)\nf = d.get('file_path', '')\nif f.endswith('/.env') or f == '.env':\n    print('BLOCKED: Direct .env edits not allowed. Edit the .env.example template instead.')\n    sys.exit(2)\n\""
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "python3 -c \"\nimport sys, json, subprocess\nd = json.load(sys.stdin)\nf = d.get('file_path', '')\nif f.endswith(('.yml', '.yaml')):\n    try:\n        import yaml\n        yaml.safe_load(open(f))\n        print(f'YAML valid: {f}')\n    except Exception as e:\n        print(f'YAML SYNTAX ERROR in {f}: {e}')\n        sys.exit(1)\n\""
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Verify hooks parse correctly**

```bash
python3 -c "import json; json.load(open('/home/jmendoza/homelab/.claude/settings.local.json')); print('JSON valid')"
```
Expected: `JSON valid`

- [ ] **Step 3: Smoke-test the .env block**

Create a throwaway test:
```bash
echo '{"file_path": "/home/jmendoza/homelab/paperless/.env"}' | python3 -c "
import sys, json
d = json.load(sys.stdin)
f = d.get('file_path', '')
if f.endswith('/.env') or f == '.env':
    print('BLOCKED')
    sys.exit(2)
"
```
Expected: prints `BLOCKED`, exit code 2.

- [ ] **Step 4: Smoke-test the YAML lint hook**

```bash
echo '{"file_path": "/home/jmendoza/homelab/docker-compose.yml"}' | python3 -c "
import sys, json, yaml
d = json.load(sys.stdin)
f = d.get('file_path', '')
if f.endswith(('.yml', '.yaml')):
    try:
        yaml.safe_load(open(f))
        print(f'YAML valid: {f}')
    except Exception as e:
        print(f'YAML SYNTAX ERROR in {f}: {e}')
        sys.exit(1)
"
```
Expected: `YAML valid: /home/jmendoza/homelab/docker-compose.yml`

---

## Task 2: Create homelab-health Skill

**Files:**
- Create: `/home/jmendoza/homelab/.claude/skills/homelab-health/SKILL.md`

This skill runs HTTP checks against every Docker service (not just `docker compose ps`) and checks K3s cluster health. The key insight: containers can show "Up" while the web server is hung (as HA demonstrated). Only HTTP 200 means truly healthy.

- [ ] **Step 1: Create skills directory and SKILL.md**

Create `/home/jmendoza/homelab/.claude/skills/homelab-health/SKILL.md`:

```markdown
---
name: homelab-health
description: Full health check for all homelab services — HTTP endpoint checks for Docker services (catches hung-but-running containers) and K3s cluster node/pod status
---

# Homelab Health Check

Run a complete health check across all Docker services and the K3s cluster. Check actual HTTP endpoints — not just container status — because containers can show "Up" while the web server is hung.

## Docker Services — HTTP Health Checks

Run these curl checks sequentially. A 200 (or redirect) = healthy. Connection refused or timeout = down.

```bash
echo "=== Docker Service Health ==="
declare -A SERVICES=(
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
  ["zigbee2mqtt"]="http://localhost:8090"
)

for name in "${!SERVICES[@]}"; do
  url="${SERVICES[$name]}"
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null)
  if [[ "$code" =~ ^[23] ]]; then
    echo "  ✓ $name ($code)"
  else
    echo "  ✗ $name — HTTP $code (url: $url)"
  fi
done
```

Then check container state for any service that failed HTTP:
```bash
docker compose ps
```

## K3s Cluster Health

```bash
echo ""
echo "=== K3s Cluster ==="
export KUBECONFIG=~/.kube/k3s-config
kubectl get nodes -o wide
echo ""
echo "--- Unhealthy Pods ---"
kubectl get pods --all-namespaces --field-selector='status.phase!=Running,status.phase!=Succeeded' 2>/dev/null || echo "All pods healthy"
```

## Interpreting Results

- **Container "Up" but HTTP ✗**: Service is hung. Run `docker compose restart <service>` to fix.
- **Node NotReady**: Check `kubectl describe node <name>` for reason.
- **Pod CrashLoopBackOff**: Run `kubectl logs -n <namespace> <pod>` for details.
- **Recurring hung services**: Check logs before restart — a blocking integration (e.g., Kasa timeout) may need to be disabled.
```

- [ ] **Step 2: Verify file exists and is valid markdown**

```bash
cat /home/jmendoza/homelab/.claude/skills/homelab-health/SKILL.md | head -5
```
Expected: Shows the frontmatter `---` and `name: homelab-health`.

---

## Task 3: Create add-service Skill

**Files:**
- Create: `/home/jmendoza/homelab/.claude/skills/add-service/SKILL.md`

This skill ensures every new Docker service gets the full homelab treatment: Watchtower label, correct volume strategy, `.env` file, K3s Service+Endpoints entry, and ingress rule — the four places that must stay in sync.

- [ ] **Step 1: Create SKILL.md**

Create `/home/jmendoza/homelab/.claude/skills/add-service/SKILL.md`:

```markdown
---
name: add-service
description: Add a new Docker Compose service following homelab patterns — covers docker-compose.yml, env file, K3s Service+Endpoints, and HTTPS ingress rule to keep all four in sync
---

# Add New Homelab Service

Adding a service requires updates in **4 places**. Work through each checklist item.

## Information to Gather First

Ask the user for:
1. **Service name** (container name, e.g. `my-service`)
2. **Docker image** (e.g. `org/image:tag`)
3. **Host port** (the port exposed on the host)
4. **Container port** (the port the app listens on inside the container)
5. **Data type**: Does it store large data (models, DBs, documents, books)? → NAS (`/mnt/synology/`). Small config/state only? → Local (`./service-name/data/`)
6. **Subdomain** for HTTPS access (e.g. `myservice.justinmendoza.net`)
7. **Dependencies**: Does it need another container to be running first?

## Step 1: Add to docker-compose.yml

Add this block to `/home/jmendoza/homelab/docker-compose.yml`, following the existing service sections:

```yaml
# ---------------------------
# <Service Name>
# ---------------------------
<service-name>:
  image: <org/image:tag>
  container_name: <service-name>
  labels:
    - "com.centurylinklabs.watchtower.enable=true"
  ports:
    - "<HOST_PORT>:<CONTAINER_PORT>"
  env_file:
    - ./<service-name>/.env
  volumes:
    # Choose based on data type:
    - /mnt/synology/<service-name>/data:/app/data    # Large/persistent (NAS-backed)
    # OR
    - ./<service-name>/data:/app/.config             # Small config/state (local)
  depends_on:                                        # Only if needed
    - <dependency>
  restart: unless-stopped
```

**Critical checks:**
- [ ] Watchtower label is present
- [ ] Uses container names (not `localhost`) for any inter-service URLs in `.env`
- [ ] Volume path matches data type decision

## Step 2: Create .env File

```bash
mkdir -p /home/jmendoza/homelab/<service-name>
touch /home/jmendoza/homelab/<service-name>/.env
touch /home/jmendoza/homelab/<service-name>/.env.example
```

Add `TZ=America/Chicago` as the baseline in both. Add all required env vars to `.env.example` with placeholder values, then fill real values in `.env` (never committed).

## Step 3: Add K3s Service + Endpoints

Add to `/home/jmendoza/homelab/k3s-manifests/docker-services.yaml`:

```yaml
---
# <Service Name> Service & Endpoints
apiVersion: v1
kind: Service
metadata:
  name: <service-name>
  namespace: docker-services
spec:
  ports:
    - port: 80
      targetPort: <HOST_PORT>
      protocol: TCP
---
apiVersion: v1
kind: Endpoints
metadata:
  name: <service-name>
  namespace: docker-services
subsets:
  - addresses:
      - ip: 100.123.171.3
    ports:
      - port: <HOST_PORT>
```

## Step 4: Add HTTPS Ingress Rule

Add to `/home/jmendoza/homelab/k3s-manifests/ingress-routes-https.yaml`:

```yaml
---
# <Service Name> Ingress with HTTPS
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: <service-name>
  namespace: docker-services
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
    - hosts:
        - <subdomain>.justinmendoza.net
      secretName: <service-name>-tls
  rules:
    - host: <subdomain>.justinmendoza.net
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: <service-name>
                port:
                  number: 80
```

## Step 5: Apply and Verify

```bash
# Start the container
docker compose up -d <service-name>
docker compose logs --tail=50 <service-name>

# Apply K3s changes
export KUBECONFIG=~/.kube/k3s-config
kubectl apply -f k3s-manifests/docker-services.yaml
kubectl apply -f k3s-manifests/ingress-routes-https.yaml

# Verify
kubectl get ingress <service-name> -n docker-services
kubectl get certificate <service-name>-tls -n docker-services
```

TLS cert provisioning takes 1-2 minutes. Check with:
```bash
kubectl describe certificate <service-name>-tls -n docker-services
```
```

- [ ] **Step 2: Verify file exists**

```bash
cat /home/jmendoza/homelab/.claude/skills/add-service/SKILL.md | head -5
```
Expected: Shows frontmatter with `name: add-service`.

---

## Task 4: Create infra-reviewer Subagent

**Files:**
- Create: `/home/jmendoza/homelab/.claude/agents/infra-reviewer.md`

This subagent validates that a newly added or modified service is consistent across the three files that must always stay in sync: `docker-compose.yml`, `docker-services.yaml`, and `ingress-routes-https.yaml`.

- [ ] **Step 1: Create agents directory and agent file**

Create `/home/jmendoza/homelab/.claude/agents/infra-reviewer.md`:

```markdown
---
name: infra-reviewer
description: Validates that Docker services are consistently defined across docker-compose.yml, k3s-manifests/docker-services.yaml, and k3s-manifests/ingress-routes-https.yaml. Use after adding or modifying any service.
---

# Homelab Infrastructure Reviewer

You are a specialized reviewer for homelab infrastructure consistency. When invoked, audit all three infrastructure files and report any mismatches or missing entries.

## What to Check

Read these three files in full:
1. `/home/jmendoza/homelab/docker-compose.yml`
2. `/home/jmendoza/homelab/k3s-manifests/docker-services.yaml`
3. `/home/jmendoza/homelab/k3s-manifests/ingress-routes-https.yaml`

For every service in docker-compose.yml that exposes a port, verify:

### Checklist per service

**docker-compose.yml:**
- [ ] Has `com.centurylinklabs.watchtower.enable=true` label
- [ ] Uses container names (not `localhost`) for inter-service references
- [ ] Has `restart: unless-stopped`
- [ ] Has `env_file` pointing to `./<service-name>/.env`
- [ ] Volume mounts follow the strategy: large data on `/mnt/synology/`, small config on `./service-name/data/`

**docker-services.yaml:**
- [ ] Has a `Service` entry with matching name in `docker-services` namespace
- [ ] Has an `Endpoints` entry pointing to `100.123.171.3` with the correct host port
- [ ] Port in Endpoints matches the host port in docker-compose.yml

**ingress-routes-https.yaml:**
- [ ] Has an `Ingress` entry with matching name in `docker-services` namespace
- [ ] Uses `letsencrypt-prod` cluster-issuer
- [ ] Has a unique `secretName` for TLS (`<service-name>-tls`)
- [ ] Host matches `*.justinmendoza.net` pattern
- [ ] Backend service name matches the Service entry in docker-services.yaml

## Output Format

Report findings as:

```
## Infrastructure Review

### ✓ Consistent Services
- service-name (port XXXX) — all three files aligned

### ✗ Issues Found
- service-name: MISSING from docker-services.yaml
- service-name: Port mismatch — compose exposes 8090, endpoints has 8080
- service-name: Missing watchtower label in docker-compose.yml
- service-name: No ingress rule in ingress-routes-https.yaml

### ⚠ Skipped (internal/no external port)
- redis, postgres, gotenberg, tika, mosquitto — internal only, no ingress needed
```

Flag every issue. Do not skip services or assume anything is intentional without checking.
```

- [ ] **Step 2: Verify file exists**

```bash
cat /home/jmendoza/homelab/.claude/agents/infra-reviewer.md | head -5
```
Expected: Shows frontmatter with `name: infra-reviewer`.

---

## Task 5: Set Up Docker MCP Server

**Files:**
- Create: `/home/jmendoza/homelab/.mcp.json`

The Docker MCP server connects to the Docker socket and lets Claude manage containers directly. Uses the official `docker/mcp-server` image.

- [ ] **Step 1: Pull the Docker MCP server image**

```bash
docker pull docker/mcp-server
```
Expected: Image pulled successfully.

- [ ] **Step 2: Create project .mcp.json**

Create `/home/jmendoza/homelab/.mcp.json`:

```json
{
  "mcpServers": {
    "docker": {
      "command": "docker",
      "args": [
        "run",
        "--rm",
        "-i",
        "--mount", "type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock",
        "docker/mcp-server"
      ]
    }
  }
}
```

- [ ] **Step 3: Verify JSON is valid**

```bash
python3 -c "import json; json.load(open('/home/jmendoza/homelab/.mcp.json')); print('valid')"
```
Expected: `valid`

- [ ] **Step 4: Add .mcp.json to .gitignore if it contains secrets (it doesn't here, so commit it)**

```bash
git -C /home/jmendoza/homelab diff --name-only
```

The `.mcp.json` has no secrets — it's safe to commit so the MCP config is version-controlled.

---

## Task 6: Set Up GitHub MCP Server

**Files:**
- Modify: `/home/jmendoza/homelab/.mcp.json`

The GitHub MCP server needs a Personal Access Token. `gh` CLI is not installed, so this task uses the token directly via environment.

- [ ] **Step 1: Install gh CLI**

```bash
(type -p wget >/dev/null || (sudo apt update && sudo apt-get install wget -y)) \
  && sudo mkdir -p -m 755 /etc/apt/keyrings \
  && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  && cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
  && sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && sudo apt update \
  && sudo apt install gh -y
```

- [ ] **Step 2: Authenticate gh CLI**

```bash
gh auth login
```
Choose: GitHub.com → HTTPS → Login with a web browser (or paste token).

- [ ] **Step 3: Add GitHub MCP to .mcp.json**

Update `/home/jmendoza/homelab/.mcp.json` to add the github entry:

```json
{
  "mcpServers": {
    "docker": {
      "command": "docker",
      "args": [
        "run",
        "--rm",
        "-i",
        "--mount", "type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock",
        "docker/mcp-server"
      ]
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "<your-token-here>"
      }
    }
  }
}
```

> **Note:** Replace `<your-token-here>` with a GitHub PAT that has `repo` scope. Create one at GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens. Since this file will contain a secret, add it to `.gitignore`.

- [ ] **Step 4: Add .mcp.json to .gitignore (now that it has a secret)**

```bash
echo ".mcp.json" >> /home/jmendoza/homelab/.gitignore
```

- [ ] **Step 5: Verify**

```bash
python3 -c "import json; json.load(open('/home/jmendoza/homelab/.mcp.json')); print('valid')"
gh auth status
```
Expected: JSON valid + `Logged in to github.com`.
