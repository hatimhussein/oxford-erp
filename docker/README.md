# FrappeDev — Docker Development Environment

Local Docker stack for **Frappe v17**, **ERPNext v17**, and **Education v17** using your existing Git clones under `D:\FrappeDev\src`. Nothing is cloned from GitHub.

---

## Folder structure

```
D:\FrappeDev\
├── src\                          # Single source of truth (your Git repos)
│   ├── frappe\
│   ├── erpnext\
│   └── education\
└── docker\                       # This development stack
    ├── docker-compose.yml        # MariaDB + Redis + Frappe/bench
    ├── Dockerfile                # Extends frappe/bench:v5.31.0 (pinned)
    ├── .env                      # Ports, passwords, site name
    ├── .gitignore
    ├── init.sh                   # Idempotent bench/site/app setup
    ├── README.md
    ├── data\
    │   └── bench\                # Created on first run (NOT in git)
    │       ├── sites\            # Site DB config, assets.json symlinks
    │       ├── env\              # Python virtualenv
    │       ├── logs\
    │       ├── config\
    │       └── apps\             # Symlinks → /workspace/src/*
    └── scripts\
        ├── entrypoint.sh         # wait → init → bench start
        ├── wait-for-services.sh
        ├── link-local-apps.sh    # Symlink local repos into bench/apps
        ├── install-node-deps.sh
        └── bench-exec.sh         # Host helper for bench CLI
```

### What lives where

| Location | Purpose | Edited in Cursor? |
|----------|---------|-------------------|
| `src/frappe`, `src/erpnext`, `src/education` | Application source + Git history | **Yes** |
| `docker/data/bench/sites` | Site config, DB name, encryption keys | Rarely |
| `docker/data/bench/env` | Python packages for bench | No (managed by bench) |
| `src/*/node_modules` | Node deps (created on init) | No (generated, gitignored) |
| `src/*/public/dist` | Built JS/CSS (after `bench build`) | No (generated, gitignored) |
| `src/education/public/frontend` | Education Vite output | No (gitignored) |
| `src/erpnext/public/banking` | ERPNext banking Vite output | No (gitignored) |

Git remotes and history in `src/*` are **never modified** by this stack.

---

## Environment review (verified)

### 1. Docker image pinning

There is **no official `frappe/bench:v17` or Frappe-framework-version tag**. The [frappe/bench](https://hub.docker.com/r/frappe/bench/tags) image tags follow **bench CLI releases** (`v5.x`), not Frappe/ERPNext version numbers.

| Setting | Value |
|---------|-------|
| Pinned tag | `frappe/bench:v5.31.0` (via `BENCH_IMAGE_TAG` in `.env`) |
| Frappe framework version | From your local `src/frappe` checkout (`17.0.0-dev`) |
| Why not `latest` | `latest` floats; pinning gives reproducible builds |

To change the bench image: edit `BENCH_IMAGE_TAG` in `.env`, then `docker compose build --no-cache frappe`.

### 2. `bench init` idempotency

`init.sh` skips `bench init` when **all** of these exist:

- `data/bench/sites/common_site_config.json`
- `data/bench/Procfile`
- `data/bench/env/bin/python`

If `docker/data/bench` is **non-empty but not a valid bench**, init **exits with an error** instead of re-running `bench init` (which would fail or corrupt). Delete `docker/data/bench` manually to start fresh.

Heavy setup (deps, build, site) runs once; marker file `data/bench/.docker-dev-init-done` skips it on later starts.

### 3. Windows + Docker Desktop + WSL2 bind mounts

Verified configuration:

- Compose uses **relative paths** (`../src/frappe`) — Docker Desktop resolves `D:\FrappeDev\src\…` correctly when compose runs from `D:\FrappeDev\docker`.
- Requires **Settings → Resources → File sharing** includes drive `D:` (or project on a shared path).
- **WSL2 backend** recommended; you may run `docker compose` from PowerShell on `D:` or from WSL at `/mnt/d/FrappeDev/docker` — both work if the path is shared.
- `:cached` on volume mounts is a macOS hint; ignored on Windows/Linux.

Verify after first start:

```powershell
docker compose exec frappe test -d /workspace/src/frappe/.git
docker compose exec frappe test -r /workspace/src/frappe/pyproject.toml
docker compose exec frappe readlink -f /home/frappe/frappe-bench/apps/frappe
# Expected: /workspace/src/frappe
```

If bind mounts fail, init prints: `Bind mount not readable at /workspace/src/…`.

### 4. Git repository safety

| Operation | Touches `src/*` Git repos? |
|-----------|----------------------------|
| `bench init --frappe-path` | **No** — creates bench under `docker/data/bench` only |
| `link-local-apps.sh` | **No** — only `rm -rf` under `bench/apps/`, then symlinks to `/workspace/src` |
| `bench setup requirements` | **No** — installs into `docker/data/bench/env` |
| `yarn install` | Writes `node_modules/` only (gitignored in all three repos) |
| `bench build` | Writes `public/dist/`, `public/frontend/`, `public/banking/` (all gitignored) |

Your `.git/` directories and tracked source files are not overwritten. Generated artifacts may appear under `src/` but are listed in each repo's `.gitignore`.

---

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) with **WSL2 backend** enabled
- **File sharing** enabled for drive `D:` (Settings → Resources → File sharing)
- Git repos already present at `D:\FrappeDev\src\{frappe,erpnext,education}`
- Shell scripts in `docker/` should use **LF** line endings (not CRLF) — CRLF can break bash in the container
- ~8 GB free disk for images + MariaDB + `node_modules` + assets

Default URLs after startup:

- Desk: `http://development.localhost:8000/app`
- Login: `Administrator` / password from `.env` (`admin` by default)

Add to hosts file if needed:

```
127.0.0.1 development.localhost
```

---

## Startup commands

From `D:\FrappeDev\docker`:

```powershell
# First time — build image and start (init runs automatically; may take 15–30 min)
docker compose up --build

# Later — detached background
docker compose up -d

# Follow logs
docker compose logs -f frappe
```

First boot will:

1. Wait for MariaDB and Redis
2. Run `bench init` using **local** `src/frappe` only
3. Symlink `src/erpnext` and `src/education` into `bench/apps/` (no `get-app` from GitHub)
4. Install Python and Node dependencies
5. Run `bench build`
6. Create site `development.localhost`
7. Install ERPNext and Education
8. Enable `developer_mode`
9. Start **web**, **socketio**, **watch**, **schedule**, and **workers** via `bench start`

---

## Stop commands

```powershell
# Stop containers, keep data
docker compose stop

# Stop and remove containers (volumes preserved)
docker compose down

# Stop and remove containers + named DB/Redis volumes (destructive)
docker compose down -v
```

To wipe only the bench runtime (keep MariaDB data):

```powershell
docker compose down
Remove-Item -Recurse -Force .\data\bench
docker compose up --build
```

---

## Rebuild commands

```powershell
# Rebuild image after Dockerfile changes
docker compose build --no-cache frappe
docker compose up -d

# Rebuild frontend/backend assets inside running container
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe bench build

# Rebuild a single app
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe bench build --app education

# Force full site reinstall (uses FORCE_REINSTALL in .env)
# Set FORCE_REINSTALL=1 in .env, then:
docker compose up --force-recreate frappe
# Set back to 0 afterward.
```

---

## Daily development workflow

### 1. Start the stack

```powershell
cd D:\FrappeDev\docker
docker compose up -d
docker compose logs -f frappe
```

### 2. Edit code in Cursor

Open workspace root `D:\FrappeDev`. Edit files under `src/`.

### 3. See changes

| Change type | Reload behavior |
|-------------|-----------------|
| Python (`.py`), DocType JSON | Auto-reload with `developer_mode=1` — refresh browser |
| Desk JS/CSS bundles | `bench watch` (in Procfile) rebuilds on save |
| Education `frontend/` | Run Vite dev separately (optional, below) |
| ERPNext `banking/` | Run Vite dev separately (optional, below) |
| New DocType / schema | Run migrate (below) |

### 4. Common bench commands

```powershell
# Migrate after schema changes
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe bench migrate

# Clear cache
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe bench --site development.localhost clear-cache

# Console
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe bench --site development.localhost console

# Run tests
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe bench --site development.localhost run-tests --app education
```

Or use the helper (Git Bash / WSL):

```bash
./scripts/bench-exec.sh migrate
./scripts/bench-exec.sh --site development.localhost clear-cache
```

### 5. Optional — SPA hot reload (Education / Banking)

In separate terminals:

```powershell
# Education student portal
docker compose exec -u frappe -w /workspace/src/education/frontend frappe yarn dev

# ERPNext banking UI
docker compose exec -u frappe -w /workspace/src/erpnext/banking frappe yarn dev
```

### 6. Git workflow

Commit inside each repo as usual — history lives in `src/*`:

```powershell
cd D:\FrappeDev\src\frappe
git status
git add .
git commit -m "your message"
```

Docker does **not** change your remotes or Git configuration.

---

## How Cursor edits appear instantly in Docker

```
Cursor (Windows)  →  saves file on disk
        ↓
D:\FrappeDev\src\frappe\...   (bind mount)
        ↓
/workspace/src/frappe/...     (same inode inside container)
        ↓
/home/frappe/frappe-bench/apps/frappe  →  symlink to /workspace/src/frappe
        ↓
bench serve / bench watch pick up changes
```

Bind mounts (`../src/frappe:cached` in `docker-compose.yml`) map host directories directly into the container. Symlinks in `data/bench/apps/` point at those mounts, so there is only one copy of the source — your local Git repos.

**Generated files** (`node_modules`, `public/dist`, `education/public/frontend`) also write through the bind mount into `src/`. Those are build artifacts, not Git-tracked source.

---

## How to update repositories

Pull latest code on the host (your remotes unchanged):

```powershell
cd D:\FrappeDev\src\frappe
git pull origin develop

cd D:\FrappeDev\src\erpnext
git pull origin develop

cd D:\FrappeDev\src\education
git pull origin develop
```

Then inside Docker:

```powershell
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe bench setup requirements
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe bash /workspace/docker/scripts/install-node-deps.sh
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe bench migrate
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe bench build
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe bench --site development.localhost clear-cache
docker compose restart frappe
```

Optional: add upstream and merge from official Frappe repos — this stack does not configure remotes for you.

---

## How to upgrade Frappe later

1. **Upgrade source** in each repo (checkout target branch/tag, pull).
2. **Rebuild dependencies and run patches:**

```powershell
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe bench setup requirements
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe bash /workspace/docker/scripts/install-node-deps.sh
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe bench migrate
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe bench build
docker compose restart frappe
```

3. **Rebuild Docker image** if the base `frappe/bench` image or Python/Node requirements changed:

```powershell
docker compose build --no-cache frappe
docker compose up -d
```

4. **Major version jumps** (e.g. v17 → v18): read Frappe migration notes, align all three apps to compatible versions, and consider wiping `docker/data/bench` for a clean bench init (export site data first).

---

## Environment variables (`.env`)

| Variable | Default | Description |
|----------|---------|-------------|
| `SITE_NAME` | `arrdh.com` | Bench site name (must match nginx site header) |
| `HOST_NAME` | `https://arrdh.com/oxforderp` | Public URL used by Frappe `get_url()` |
| `ADMIN_PASSWORD` | `admin` | Administrator password |
| `MARIADB_ROOT_PASSWORD` | `admin` | MariaDB root password |
| `WEB_PORT` | `8000` | Frappe HTTP port (bound to `127.0.0.1` only) |
| `SOCKETIO_PORT` | `9000` | Socket.IO port (bound to `127.0.0.1` only) |
| `PROXY_PORT` | `8088` | Docker nginx reverse proxy (`127.0.0.1`) |
| `DEVELOPER_MODE` | `0` | Enables Python auto-reload when `1` |
| `SKIP_ASSETS_BUILD` | `0` | Set `1` to skip `bench build` on init |
| `FORCE_REINSTALL` | `0` | Set `1` to drop and recreate site on init |

---

## Public URL: https://arrdh.com/oxforderp

Traffic flow: browser (HTTPS on host) → host Apache/Nginx → `127.0.0.1:8088` (Docker nginx) → Frappe.

### 1. Start stack

```bash
cd /home/arrdh.com/oxforderp/docker
docker compose up -d
```

### 2. Configure Frappe host_name

```bash
bash scripts/configure-oxforderp-host.sh
# or:
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe \
  bench --site arrdh.com set-config host_name "https://arrdh.com/oxforderp"
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe \
  bench --site arrdh.com clear-cache
```

If the existing site folder is still `development.localhost`, either rename it to `arrdh.com` under `data/bench/sites/` or change `SITE_NAME` / nginx `X-Frappe-Site-Name` to match the real site name.

### 3. Host SSL reverse proxy

Add the Apache or Nginx block from [`nginx/host-arrdh-oxforderp.conf`](nginx/host-arrdh-oxforderp.conf) to the HTTPS vhost for `arrdh.com`, then reload the host web server.

### 4. Open

- App: https://arrdh.com/oxforderp/desk
- Example: https://arrdh.com/oxforderp/desk/assets

Do **not** expose `:8000` publicly; it is bound to localhost only.

---

## Services

| Service | Container | Role |
|---------|-----------|------|
| MariaDB 11.8 | `frappedev-mariadb` | Database |
| Redis 7 | `frappedev-redis` | Cache, queue, Socket.IO |
| Frappe | `frappedev-frappe` | web, socketio, watch, schedule, workers |
| Nginx | `frappedev-nginx` | Path-prefix reverse proxy (`/oxforderp`) |

Procfile processes (via `bench start`):

- **web** — `bench serve` on port 8000
- **socketio** — real-time desk updates
- **watch** — asset hot rebuild (`bench watch`)
- **schedule** — cron-style scheduled jobs
- **worker** — background job workers (short/default/long queues)

---

## Troubleshooting

| Issue | Action |
|-------|--------|
| Port 8000 in use | Change `WEB_PORT` in `.env` |
| Init stuck on MariaDB | `docker compose logs mariadb` — wait for healthy status |
| Assets missing / 404 | `docker compose exec … frappe bench build` |
| Permission errors on Windows | Use WSL2 backend in Docker Desktop; keep repos on a local drive |
| Site broken after pull | `bench migrate` + `bench clear-cache` + restart |
| Full reset | `docker compose down`, delete `data/bench`, `docker compose up --build` |

---

## Design decisions

- **No GitHub clones** — apps are symlinked from `/workspace/src/*`.
- **No `bench get-app` from remote** — only local paths via symlinks.
- **Git history preserved** — bind mounts include `.git` directories.
- **Bench runtime isolated** — `docker/data/bench` holds sites/env, not your app repos.
- **Developer mode + watch** — Python and asset hot reload for daily dev.

---

## Quick reference

```powershell
# Start
docker compose up -d

# Logs
docker compose logs -f frappe

# Shell inside bench
docker compose exec -u frappe -w /home/frappe/frappe-bench frappe bash

# Stop
docker compose stop
```
