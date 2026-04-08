# Plex Media Stack Design

## Context

Add a complete media server and automated media pipeline to the existing Docker Compose homelab. The goal is to stream an existing personal media library and automate discovery/download/organization of new movies and TV shows.

## Approach

All services added to the existing `docker-compose.yml` on the GPU host (Approach A). Single compose file, shared GPU, local media storage, hardlink-capable file moves.

## Services

| Service | Image | Port | Purpose |
|---------|-------|------|---------|
| Plex | `plexinc/pms-docker:latest` | 32400 | Media server with GPU transcoding |
| Radarr | `linuxserver/radarr:latest` | 7878 | Movie management & automation |
| Sonarr | `linuxserver/sonarr:latest` | 8989 | TV show management & automation |
| Prowlarr | `linuxserver/prowlarr:latest` | 9696 | Indexer manager for Radarr/Sonarr |
| Bazarr | `linuxserver/bazarr:latest` | 6767 | Subtitle auto-downloader |
| SABnzbd | `linuxserver/sabnzbd:latest` | 8082 | Usenet download client |
| qBittorrent | `linuxserver/qbittorrent:latest` | 8081 | Torrent download client |

All LinuxServer.io images use `PUID=1000`/`PGID=1000` for consistent file ownership. All services get the Watchtower label and `restart: unless-stopped`.

## Storage Layout

### Config (local, fast, small)

Following existing pattern `./service-name/data/`:

- `./plex/data/` - Plex config, database, metadata
- `./radarr/data/` - Radarr config & database
- `./sonarr/data/` - Sonarr config & database
- `./prowlarr/data/` - Prowlarr config & database
- `./bazarr/data/` - Bazarr config & database
- `./sabnzbd/data/` - SABnzbd config & database
- `./qbittorrent/data/` - qBittorrent config & database

### Media (local disk, `/mnt/e/media/`)

```
/mnt/e/media/
├── Anime Movies/       # existing Plex library
├── Asian Dramas/       # existing Plex library
├── Asian Movies/       # existing Plex library
├── Workout/            # existing Plex library
├── anime/              # existing Plex library
├── tvshows/            # existing Plex library
├── movies/             # NEW - Radarr-managed movies
├── tv/                 # NEW - Sonarr-managed TV shows
└── downloads/          # NEW - staging area
    ├── usenet/
    │   ├── complete/
    │   └── incomplete/
    └── torrents/
        ├── complete/
        └── incomplete/
```

All containers mount `/mnt/e/media` at `/media` internally. This shared mount point enables hardlink moves (instant, zero-copy) from downloads into library folders.

## GPU & Transcoding

Plex shares the NVIDIA GPU with Ollama using the same passthrough pattern:

```yaml
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: all
          capabilities: [gpu]
environment:
  - NVIDIA_VISIBLE_DEVICES=all
  - NVIDIA_DRIVER_CAPABILITIES=compute,video,utility
```

The `video` capability (added beyond Ollama's `compute,utility`) enables NVENC/NVDEC for hardware transcoding. LLM inference and video transcoding use different hardware blocks on the GPU and coexist without conflict.

User has a lifetime Plex Pass, so all premium features including GPU transcoding are available.

## Data Flow

```
Prowlarr ──manages indexers for──> Radarr ──sends downloads to──> SABnzbd / qBittorrent
                                   Sonarr ──sends downloads to──> SABnzbd / qBittorrent

Radarr/Sonarr ──move completed files──> /media/movies & /media/tv

Bazarr ──connects to Radarr/Sonarr APIs──> fetches subtitles for library content

Plex ──scans & serves──> /media/* (all library folders)
```

- Prowlarr: single source of truth for indexers, syncs to Radarr/Sonarr
- Radarr/Sonarr: tell download clients what to grab, move/rename completed files
- Bazarr: reads Radarr/Sonarr APIs for media inventory, fetches matching subtitles
- Plex: watches library folders only, no direct *arr connection needed
- Download strategy: Usenet (SABnzbd) primary, torrents (qBittorrent) fallback

## Environment Variables

Each service gets `./service-name/.env` (gitignored). Common variables for LinuxServer.io containers:

```env
PUID=1000
PGID=1000
TZ=America/New_York
```

Plex additionally needs:

```env
PLEX_CLAIM=<claim-token-from-plex.tv/claim>
```

One-time token to link server to Plex account. Expires 4 minutes after generation.

## K3s Integration

Expose services via K3s Traefik ingress using the existing ExternalName pattern:

### docker-services.yaml

Add Service + Endpoints entries pointing to `100.123.171.3` for:
- Plex (port 32400)
- Radarr (port 7878)
- Sonarr (port 8989)
- Prowlarr (port 9696)
- Bazarr (port 6767)
- SABnzbd (port 8082)
- qBittorrent (port 8081)

### ingress-routes-https.yaml

Add IngressRoute entries with TLS (cert-manager, `letsencrypt-prod`) for:
- `plex.justinmendoza.net` -> Plex
- `radarr.justinmendoza.net` -> Radarr
- `sonarr.justinmendoza.net` -> Sonarr
- `prowlarr.justinmendoza.net` -> Prowlarr
- `bazarr.justinmendoza.net` -> Bazarr
- `sabnzbd.justinmendoza.net` -> SABnzbd
- `qbittorrent.justinmendoza.net` -> qBittorrent

## Port Summary (after additions)

No conflicts with existing services:

| Port | Service | Status |
|------|---------|--------|
| 6767 | Bazarr | NEW |
| 7878 | Radarr | NEW |
| 8081 | qBittorrent | NEW |
| 8082 | SABnzbd | NEW |
| 8989 | Sonarr | NEW |
| 9696 | Prowlarr | NEW |
| 32400 | Plex | NEW |

## Files to Modify

1. `docker-compose.yml` - Add all 7 services
2. `k3s-manifests/docker-services.yaml` - Add Service + Endpoints for each
3. `k3s-manifests/ingress-routes-https.yaml` - Add IngressRoute for each
4. Create `./plex/.env`, `./radarr/.env`, `./sonarr/.env`, `./prowlarr/.env`, `./bazarr/.env`, `./sabnzbd/.env`, `./qbittorrent/.env`
5. Create media directories: `/mnt/e/media/movies/`, `/mnt/e/media/tv/`, `/mnt/e/media/downloads/{usenet,torrents}/{complete,incomplete}/`

## Post-Setup Configuration

After containers are running, configure via web UIs:

1. **Plex** (`:32400/web`) - Add libraries pointing to `/media/movies`, `/media/tv`, and existing folders. Enable hardware transcoding in Settings > Transcoder.
2. **Prowlarr** (`:9696`) - Add Usenet indexers and torrent indexers. Add Radarr/Sonarr as applications.
3. **SABnzbd** (`:8082`) - Add Usenet provider credentials. Set download paths.
4. **qBittorrent** (`:8081`) - Configure download paths. Optional: VPN setup for privacy.
5. **Radarr** (`:7878`) - Add root folder `/media/movies`. Connect to Prowlarr, SABnzbd, qBittorrent.
6. **Sonarr** (`:8989`) - Add root folder `/media/tv`. Connect to Prowlarr, SABnzbd, qBittorrent.
7. **Bazarr** (`:6767`) - Connect to Radarr/Sonarr APIs. Configure subtitle providers.

## Verification

1. `docker compose up -d plex radarr sonarr prowlarr bazarr sabnzbd qbittorrent` - all containers start
2. Each web UI is accessible on its port
3. Plex detects GPU: Settings > Transcoder shows "Use hardware acceleration" option
4. Prowlarr can sync indexers to Radarr/Sonarr
5. Radarr/Sonarr can connect to SABnzbd and qBittorrent
6. K3s ingress routes resolve and proxy to Docker services
