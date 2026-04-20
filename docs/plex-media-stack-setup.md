# Plex Media Stack Setup Guide

All services are running. This guide walks through configuring each app in the correct order.

## Setup Order

1. SABnzbd (Usenet downloader)
2. qBittorrent (Torrent downloader)
3. Prowlarr (Indexer manager)
4. Radarr (Movies)
5. Sonarr (TV Shows)
6. Bazarr (Subtitles)
7. Homepage (Dashboard)

---

## 1. SABnzbd — `localhost:8082`

SABnzbd downloads files from Usenet. You'll need a Usenet provider subscription.

### First Launch

1. Open `localhost:8082` — the setup wizard starts automatically
2. Set language and click through to server setup

### Add Usenet Provider

1. Go to **Config > Servers**
2. Click **Add Server** and enter your provider details:
   - Host: (from your provider, e.g., `news.newshosting.com`)
   - Port: `563` (SSL) or `119` (non-SSL)
   - SSL: **Yes**
   - Username / Password: (from your provider)
   - Connections: start with `10`, adjust based on provider plan
3. Click **Test Server** to verify, then **Save**

### Popular Usenet Providers

| Provider | Price | Notes |
|----------|-------|-------|
| Newshosting | ~$3/mo (annual) | US backbone, unlimited |
| Eweka | ~$4/mo (annual) | EU backbone, good completion |
| Frugal Usenet | ~$4/mo | Budget option, block accounts available |

Having one US and one EU provider gives best coverage for older content.

### Set Download Paths

1. Go to **Config > Folders**
2. Set **Temporary Download Folder** to `/media/downloads/usenet/incomplete`
3. Set **Completed Download Folder** to `/media/downloads/usenet/complete`
4. Save

### Get the API Key

1. Go to **Config > General**
2. Copy the **API Key** — you'll need this for Radarr/Sonarr later

---

## 2. qBittorrent — `localhost:8081`

qBittorrent downloads torrents. Consider using a VPN for privacy.

### First Login

1. Open `localhost:8081`
2. Default credentials:
   - Username: `admin`
   - Password: check the container logs for the temporary password:
     ```bash
     docker compose logs qbittorrent | grep "temporary password"
     ```
3. **Change the password immediately** in Settings > Web UI

### Set Download Paths

1. Go to **Settings > Downloads**
2. Set **Default Save Path** to `/media/downloads/torrents/complete`
3. Check **Keep incomplete torrents in** and set to `/media/downloads/torrents/incomplete`
4. Save

### Recommended Settings

1. **Settings > BitTorrent**
   - Enable **Seeding Limits** if you want to stop seeding after a ratio (e.g., 1.0)
2. **Settings > Connection**
   - Listening port: default `6881` is fine for local use
3. **Settings > Web UI**
   - Check **Bypass authentication for clients on localhost** if desired

---

## 3. Prowlarr — `localhost:9696`

Prowlarr manages indexers (search sources) and syncs them to Radarr/Sonarr so you only configure them once.

### First Launch

1. Open `localhost:9696`
2. Set up authentication (username/password)

### Add Indexers

Indexers are search providers. You'll want both Usenet and Torrent indexers.

**Usenet Indexers** (require accounts, some are invite-only):

| Indexer | Type | Notes |
|---------|------|-------|
| NZBgeek | Usenet | Popular, easy to join, $12/year | YwoQJMI4nQrIpXJFibDNM2kjbbjFGkZQ
| DrunkenSlug | Usenet | Good general indexer, free tier available |
| NZBFinder | Usenet | Free tier with limits |

**Torrent Indexers** (many are public/free):

| Indexer | Type | Notes |
|---------|------|-------|
| 1337x | Public torrent | No account needed |
| RARBG (via Torznab) | Public torrent | No account needed |
| IPTorrents | Private torrent | Invite-only, high quality |

To add an indexer:
1. Go to **Indexers > Add Indexer**
2. Search for the indexer name
3. Enter your API key / credentials for that indexer
4. **Test** and **Save**

### Connect Radarr & Sonarr

1. Go to **Settings > Apps**
2. Click **+** and select **Radarr**
   - Prowlarr Server: `http://prowlarr:9696`
   - Radarr Server: `http://radarr:7878`
   - API Key: (get from Radarr > Settings > General > API Key)
   - Click **Test** then **Save**
3. Click **+** and select **Sonarr**
   - Prowlarr Server: `http://prowlarr:9696`
   - Sonarr Server: `http://sonarr:8989`
   - API Key: (get from Sonarr > Settings > General > API Key)
   - Click **Test** then **Save**

Prowlarr will now automatically sync all your indexers to both apps.

---

## 4. Radarr — `localhost:7878`

Radarr automates movie downloads. Search for a movie, Radarr finds it, sends it to SABnzbd/qBittorrent, and organizes it into your Plex library.

### First Launch

1. Open `localhost:7878`
2. Set up authentication (Settings > General > Authentication)

### Add Root Folder

1. Go to **Settings > Media Management**
2. Click **Add Root Folder**
3. Enter `/media/movies`
4. Save

### Connect Download Clients

1. Go to **Settings > Download Clients**
2. Click **+** and select **SABnzbd**
   - Host: `sabnzbd`
   - Port: `8080`
   - API Key: (from SABnzbd Config > General)
   - Category: `movies` (SABnzbd will auto-create this)
   - Click **Test** then **Save**
3. Click **+** and select **qBittorrent**
   - Host: `qbittorrent`
   - Port: `8080`
   - Username: `admin`
   - Password: (your qBittorrent password)
   - Category: `movies`
   - Click **Test** then **Save**

### Set Quality Profile

1. Go to **Settings > Profiles**
2. Edit the **HD-1080p** profile (good default):
   - Ensure Bluray-1080p, WEB-DL 1080p, and WEBRip-1080p are checked
   - Set upgrade until quality to your preference
3. Or create a custom profile if you prefer 4K

### Add Your First Movie

1. Click **Add New** in the sidebar
2. Search for a movie
3. Select root folder `/media/movies`
4. Choose quality profile
5. Click **Add Movie**
6. Radarr will search your indexers and start downloading automatically

---

## 5. Sonarr — `localhost:8989`

Sonarr is the same as Radarr but for TV shows. It tracks seasons/episodes and downloads new episodes as they air.

### First Launch

1. Open `localhost:8989`
2. Set up authentication (Settings > General > Authentication)

### Add Root Folder

1. Go to **Settings > Media Management**
2. Click **Add Root Folder**
3. Enter `/media/tv`
4. Save

### Connect Download Clients

1. Go to **Settings > Download Clients**
2. Add **SABnzbd** (same as Radarr, but set Category to `tv`)
   - Host: `sabnzbd`
   - Port: `8080`
   - API Key: (same SABnzbd API key)
   - Category: `tv`
3. Add **qBittorrent** (same as Radarr, but set Category to `tv`)
   - Host: `qbittorrent`
   - Port: `8080`
   - Username/Password: (same qBittorrent credentials)
   - Category: `tv`

### Add Your First Show

1. Click **Add New**
2. Search for a TV show
3. Select root folder `/media/tv`
4. Choose which seasons to monitor
5. Click **Add**
6. Sonarr will search and download automatically, and grab new episodes as they air

---

## 6. Bazarr — `localhost:6767`

Bazarr automatically downloads subtitles for your movies and TV shows.

### First Launch

1. Open `localhost:6767`
2. Set up authentication

### Connect to Radarr & Sonarr

1. Go to **Settings > Radarr**
   - Enable Radarr
   - Host: `radarr`
   - Port: `7878`
   - API Key: (from Radarr > Settings > General)
   - Click **Test** then **Save**
2. Go to **Settings > Sonarr**
   - Enable Sonarr
   - Host: `sonarr`
   - Port: `8989`
   - API Key: (from Sonarr > Settings > General)
   - Click **Test** then **Save**

### Add Subtitle Providers

1. Go to **Settings > Providers**
2. Click **+** and add providers. Good free options:
   - **OpenSubtitles.com** (free account, most popular)
   - **Addic7ed** (good for TV shows)
   - **Podnapisi** (good secondary source)
3. Set your preferred subtitle languages in **Settings > Languages**

---

## 7. Homepage — `localhost:3001`

Homepage auto-discovers your Docker containers, but you can customize it further.

### Configuration Files

Homepage stores config in `./homepage/config/`. The key files:

- `services.yaml` — your service groups and links
- `widgets.yaml` — top-bar widgets
- `docker.yaml` — Docker integration (already connected)

### Adding Service Widgets with Live Stats

Edit `./homepage/config/services.yaml` to add API integrations. Example:

```yaml
- Media:
    - Plex:
        icon: plex
        href: https://plex.justinmendoza.net
        widget:
          type: plex
          url: http://plex:32400
          key: YOUR_PLEX_TOKEN

    - Radarr:
        icon: radarr
        href: https://radarr.justinmendoza.net
        widget:
          type: radarr
          url: http://radarr:7878
          key: YOUR_RADARR_API_KEY

    - Sonarr:
        icon: sonarr
        href: https://sonarr.justinmendoza.net
        widget:
          type: sonarr
          url: http://sonarr:8989
          key: YOUR_SONARR_API_KEY

- Downloads:
    - SABnzbd:
        icon: sabnzbd
        href: https://sabnzbd.justinmendoza.net
        widget:
          type: sabnzbd
          url: http://sabnzbd:8080
          key: YOUR_SABNZBD_API_KEY

    - qBittorrent:
        icon: qbittorrent
        href: https://qbittorrent.justinmendoza.net
        widget:
          type: qbittorrent
          url: http://qbittorrent:8080
          username: admin
          password: YOUR_QBITTORRENT_PASSWORD

- Documents:
    - Paperless:
        icon: paperless-ngx
        href: https://paperless.justinmendoza.net
        widget:
          type: paperless
          url: http://paperless:8000
          key: YOUR_PAPERLESS_TOKEN

- AI:
    - Open WebUI:
        icon: open-webui
        href: https://openwebui.justinmendoza.net

    - Ollama:
        icon: ollama
        href: https://ollama.justinmendoza.net
```

Homepage reloads config automatically — no restart needed after editing.

### Getting API Keys

| Service | Where to find it |
|---------|-----------------|
| Plex | Account > Authorized Devices, or see [finding your Plex token](https://support.plex.tv/articles/204059436/) |
| Radarr | Settings > General > API Key |
| Sonarr | Settings > General > API Key |
| SABnzbd | Config > General > API Key |
| Prowlarr | Settings > General > API Key |
| qBittorrent | Uses username/password (no API key) |
| Paperless | Settings > API tokens |

---

## Quick Reference

### Service URLs (local)

| Service | URL | Purpose |
|---------|-----|---------|
| Plex | `localhost:32400/web` | Media streaming |
| Radarr | `localhost:7878` | Movie management |
| Sonarr | `localhost:8989` | TV show management |
| Prowlarr | `localhost:9696` | Indexer management |
| Bazarr | `localhost:6767` | Subtitle downloads |
| SABnzbd | `localhost:8082` | Usenet downloads |
| qBittorrent | `localhost:8081` | Torrent downloads |
| Homepage | `localhost:3001` | Dashboard |

### Inter-Service Communication

All services communicate using **container names** (not localhost):

| From | To | Address |
|------|----|---------|
| Radarr/Sonarr | SABnzbd | `sabnzbd:8080` |
| Radarr/Sonarr | qBittorrent | `qbittorrent:8080` |
| Prowlarr | Radarr | `radarr:7878` |
| Prowlarr | Sonarr | `sonarr:8989` |
| Bazarr | Radarr | `radarr:7878` |
| Bazarr | Sonarr | `sonarr:8989` |
| Homepage | All services | `<container-name>:<internal-port>` |

### Media Paths (inside containers)

| Path | Purpose |
|------|---------|
| `/media/movies` | Radarr-managed movie library |
| `/media/tv` | Sonarr-managed TV library |
| `/media/downloads/usenet/complete` | SABnzbd completed downloads |
| `/media/downloads/usenet/incomplete` | SABnzbd in-progress |
| `/media/downloads/torrents/complete` | qBittorrent completed downloads |
| `/media/downloads/torrents/incomplete` | qBittorrent in-progress |
| `/media/Anime Movies` | Existing Plex library |
| `/media/Asian Dramas` | Existing Plex library |
| `/media/Asian Movies` | Existing Plex library |
| `/media/anime` | Existing Plex library |
| `/media/tvshows` | Existing Plex library |
| `/media/Workout` | Existing Plex library |
