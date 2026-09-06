# Medusa v2 for Railway — Server + Worker, Postgres + Redis

One-click [Medusa v2](https://github.com/medusajs/medusa) deployment for [Railway](https://railway.com): a production topology exactly as the [official deployment guide](https://docs.medusajs.com/learn/deployment/general) prescribes — **API/admin server**, **background worker**, **PostgreSQL**, and **Redis**, pre-wired and talking to each other over the Redis event bus.

Deploys with **Medusa `2.20.1`** (pinned). Open the admin dashboard at `/app` right after deploying.

```
                          ┌────────────────────┐
   HTTPS /health /app /store ──▶   medusa-server  │──────┐
                          │  MEDUSA_WORKER_MODE=server  │      │
                          └──────────┬─────────┘      │
                                     │ events, cache, │
                                     │ locks, workflows│
                          ┌──────────▼─────────┐   ┌──▼─────────┐
                          │      Redis         │   │  Postgres  │
                          └──────────▲─────────┘   └──▲─────────┘
                                     │                │
                          ┌──────────┴─────────┐      │
                          │   medusa-worker    │──────┘
                          │  MEDUSA_WORKER_MODE=worker
                          └────────────────────┘
```

- **medusa-server** — serves the Store/Admin APIs and the admin dashboard (`/app`) on port 9000, runs migrations on boot, registers your admin user.
- **medusa-worker** — same image, `MEDUSA_WORKER_MODE=worker`, no public domain. Handles subscribers, scheduled jobs and workflows. Scale it independently.
- **Postgres** — primary datastore (`${{Postgres.DATABASE_URL}}` referenced automatically).
- **Redis** — event bus (BullMQ), workflow engine, cache and locks (`${{Redis.REDIS_URL}}` referenced automatically). This is what makes the server↔worker split work: both consume the same event stream.

## Why this template

| | This template | Typical v1-era templates |
|---|---|---|
| Topology | Official server + worker split | single container or v1 worker modes |
| Version | **2.20.1 pinned** (post-`event-bus-redis` fix, ≥2.17.1) | v1, end-of-life |
| Migrations | `medusa db:migrate` before every serve, idempotent | manual / missing |
| Admin | reachable at `/app`, user auto-created from env vars | often locked out |
| Redis on Railway | `family=0` IPv6 fix baked in | hangs/dropped events |
| Production modules | Redis event bus, workflow engine, cache, locking | in-memory defaults |

## Post-deploy checklist (2 minutes)

1. Wait for both Medusa services to show a green **/health** (first boot runs migrations; usually < 2–3 min).
2. Open **`https://<your-medusa-server-domain>/app`** and log in with `MEDUSA_ADMIN_EMAIL` / `MEDUSA_ADMIN_PASSWORD` (you set these in the deploy config; defaults are provided if you didn't).
3. **Change the admin password** in Settings → Personal information (or set strong env values before deploying).
4. Grab your publishable API key: Settings → **Publishable API Keys** — storefronts send it as `x-publishable-api-key`.
5. Point your storefront at the backend:
   - API base URL: `https://<your-medusa-server-domain>` (Store API under `/store`)
   - Add the storefront's origin to `STORE_CORS` and `AUTH_CORS` on **medusa-server**, then redeploy it.
   - Next.js starter: see [Connecting a storefront](#connecting-a-storefront).

## Connecting a storefront

The template ships the commerce backend; bring any storefront. With the official Next.js starter:

1. Deploy the starter to Railway (or run it locally) and set:
   - `MEDUSA_BACKEND_URL=https://<your-medusa-server-domain>`
   - `NEXT_PUBLIC_MEDUSA_BACKEND_URL=https://<your-medusa-server-domain>`
   - `NEXT_PUBLIC_DEFAULT_REGION=us` (or your region)
   - `NEXT_PUBLIC_PUBLISHABLE_KEY=<key from step 4 above>`
2. On **medusa-server**, add the storefront origin to `STORE_CORS` and `AUTH_CORS` (comma-separated), e.g. `https://your-storefront.up.railway.app`, and redeploy.

## Environment variables

Set automatically by the template (reference variables — don't hardcode):

| Variable | medusa-server | medusa-worker | Notes |
|---|---|---|---|
| `DATABASE_URL` | `${{Postgres.DATABASE_URL}}` | `${{Postgres.DATABASE_URL}}` | Postgres |
| `REDIS_URL` | `${{Redis.REDIS_URL}}` | `${{Redis.REDIS_URL}}` | `family=0` appended automatically |
| `JWT_SECRET` / `COOKIE_SECRET` | generated | generated | required in production |
| `MEDUSA_WORKER_MODE` | `server` | `worker` | |
| `DISABLE_MEDUSA_ADMIN` | derived | derived | defaults to `true` on worker, `false` otherwise |
| `MIGRATE_ON_BOOT` | `true` | skipped | worker never migrates (derived from mode) |

Set by you (configurable at deploy time):

| Variable | Default | Notes |
|---|---|---|
| `MEDUSA_ADMIN_EMAIL` | `admin@medusa-example.com` | admin user created on first boot |
| `MEDUSA_ADMIN_PASSWORD` | generated | change after first login |
| `MEDUSA_BACKEND_URL` | your server domain | admin ↔ backend URL |
| `ADMIN_CORS` | your server domain | admin dashboard origin |
| `STORE_CORS` | `http://localhost:3000,...` | storefront origins, comma-separated |
| `AUTH_CORS` | server domain + storefront | every authenticating origin, comma-separated |
| `PORT` | `9000` | |

## Operations

### Migrations on boot

`start.sh` runs `npm run predeploy` (`medusa db:migrate`) **before** `medusa start` on every deploy of **medusa-server**. Migrations are idempotent — Medusa tracks applied migrations in the database, so re-running is a no-op. The worker skips migrations (`MIGRATE_ON_BOOT=false`), so schema changes have exactly one owner. Restart/redeploy the server at any time: migrate → serve ordering is preserved.

### Scaling

- **medusa-worker** is stateless — scale it to N instances (Railway → Service → Metrics/Replicas). Each instance joins the same BullMQ queues via Redis.
- Keep **medusa-server** at 1 instance unless you add a load balancer in front; Railway's domain proxies to one instance.
- Minimum sizes: 1 GB RAM for medusa-server (admin is the heavy part), 512 MB–1 GB for the worker. Postgres 1 GB, Redis 256 MB+ to start. A small store runs ≈ **$15–30/month** total on Railway.

### Upgrading Medusa (pinned version)

The version is pinned in `package.json` (every `@medusajs/*` package, currently `2.20.1`). To upgrade:

1. Check the [release notes](https://github.com/medusajs/medusa/releases) for breaking changes.
2. Bump **all** `@medusajs/*` packages to the same version:
   ```bash
   npm install @medusajs/medusa@2.x.y @medusajs/framework@2.x.y @medusajs/cli@2.x.y \
     @medusajs/admin-sdk@2.x.y @medusajs/admin-shared@2.x.y @medusajs/caching@2.x.y \
     @medusajs/caching-redis@2.x.y @medusajs/dashboard@2.x.y @medusajs/draft-order@2.x.y \
     @medusajs/test-utils@2.x.y --save-exact
   ```
3. Deploy to a **staging** project first: migrations run automatically on boot; verify `/health`, `/app`, and a test order end-to-end.
4. Update the version badge/README pin, commit, deploy to production.

> Historical note: Medusa **2.17.0** shipped a regression that made `event-bus-redis` hang at "Creating server" ([#15835](https://github.com/medusajs/medusa/issues/15835), fixed in 2.17.1). This template never pins a version below 2.17.1 for that reason — if you bump and the server hangs at "Creating server", check that issue first.

### Local development

```bash
cp .env.template .env      # fill in DATABASE_URL (any Postgres) — REDIS_URL optional
npm install
npm run dev                # in-memory event bus/cache when REDIS_URL is unset
npm run build && npm run predeploy && npm run start   # production build locally
```

### Repo layout

```
├── medusa-config.ts     # worker mode, Redis modules, admin config
├── src/                 # your customizations (api, jobs, modules, subscribers, workflows)
├── Dockerfile           # single image for server + worker (admin built in)
├── start.sh             # migrate → admin bootstrap → serve
└── railway.json         # builder + healthcheck config
```

## Troubleshooting

**Server hangs at "Creating server"** — you are on a Medusa version with the `event-bus-redis` regression ([#15835](https://github.com/medusajs/medusa/issues/15835), only 2.17.0). This template pins ≥2.17.1; if you bumped, move to ≥2.17.1.

**Worker not processing events** — check the worker service is running (`MEDUSA_WORKER_MODE=worker`) and both services reference the *same* `REDIS_URL`. The event bus is Redis-backed; server and worker must share that Redis. Verify with a round-trip: create a product in the admin → the worker logs the `product.created` subscriber activity.

**Migrations fail at boot** — check `DATABASE_URL` resolves (Postgres service running). Logs show `migrations complete` before `starting Medusa...`; if a deploy fails healthcheck but logs show migrations done, the server likely started before Postgres finished provisioning — restart the deploy once.

**Locked out of the admin** — the bootstrap runs only when the user doesn't exist. If you lost the password, set a new `MEDUSA_ADMIN_PASSWORD` and delete the row via `railway connect postgres` (or run `npx medusa user -e you@example.com -p newpass` inside the medusa-server shell) — or use the "Forgot password" flow if email is configured.

**Admin at `/app` shows a blank page or API errors** — `MEDUSA_BACKEND_URL` / `ADMIN_CORS` must be the public `https://…railway.app` domain of medusa-server, and the service must have a public domain. After changing either, redeploy.

**Redis connection errors on Railway** — Railway's internal Redis proxy speaks IPv6; the template appends `family=0` to `REDIS_URL` automatically in `medusa-config.ts`. If you supply your own external Redis, no change is needed.

## Deploy

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/medusa-v2)

Click the button and you're done — no deploy-form questions. Secrets are auto-generated, services are referenced automatically, and migrations run on boot. After deploying, grab the auto-generated admin password from `medusa-server` → **Variables** → `MEDUSA_ADMIN_PASSWORD` and log in at `/app`.

---

Built on [Medusa v2](https://docs.medusajs.com) (MIT). Template MIT licensed. Medusa Cloud is the zero-ops alternative — see the [comparison](https://docs.medusajs.com/cloud/comparison).
