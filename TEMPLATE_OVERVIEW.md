<p align="center">
  <a href="https://www.medusajs.com" target="_blank"><img src="https://raw.githubusercontent.com/medusajs/medusa/develop/www/docs/static/img/logo-dark.svg" alt="Medusa" width="220"></a>
</p>

# Medusa v2 — Shopify Alternative (Server + Worker)

One-click **Medusa v2** deployment on Railway with the exact production topology the [official deployment guide](https://docs.medusajs.com/learn/deployment/general) prescribes: an **API + admin server**, a **background worker**, **PostgreSQL**, and **Redis**, all pre-wired. Medusa is the open-source headless commerce engine — your own Shopify alternative with products, carts, orders, promotions, taxes, inventory, and fulfillment modules.

No deploy-form questions: secrets are auto-generated, services are referenced automatically, and migrations run on boot. Open the admin dashboard at `/app` right after deploying.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/medusa-v2)

## What you get

- **medusa-server** — Store & Admin APIs plus the admin dashboard (`/app`) on port 9000, public domain included
- **medusa-worker** — same image, `MEDUSA_WORKER_MODE=worker`, no public domain; runs subscribers, scheduled jobs, and workflows consumed via the Redis event bus (BullMQ)
- **Postgres** — primary datastore, wired via `${{Postgres.DATABASE_URL}}`
- **Redis** — event bus, workflow engine, cache, and locks wired via `${{Redis.REDIS_URL}}` (with the `family=0` IPv6 fix baked in — the classic Railway Redis hang, solved)
- **Migrations on boot** — `medusa db:migrate` runs before every server start (idempotent; the worker never migrates)
- **Admin bootstrap** — an admin user is created on first boot; the password is auto-generated (grab it from `medusa-server` → Variables → `MEDUSA_ADMIN_PASSWORD`)
- **Demo store included** — regions, currencies, sales channel, publishable API key, and sample products are seeded on first boot, so the Store API works immediately
- **Medusa `2.20.1` pinned** — never a version with the [2.17.0 event-bus hang regression](https://github.com/medusajs/medusa/issues/15835); the bump procedure is documented in the repo README

## After deploying (2 minutes)

1. Wait for `medusa-server` and `medusa-worker` to go green (first boot: migrations + seed, usually under 3 minutes).
2. Get your admin password: `medusa-server` service → **Variables** → `MEDUSA_ADMIN_PASSWORD`.
3. Log in at `https://<your-medusa-server-domain>/app` with `admin@example.com` (or set `MEDUSA_ADMIN_EMAIL` before deploying) — then change the password.
4. Copy your publishable API key from Settings → **Publishable API Keys** for storefront calls.
5. Point a storefront at the backend: set the storefront origin in `STORE_CORS` / `AUTH_CORS` on `medusa-server` and redeploy. The [Next.js starter](https://docs.medusajs.com/nextjs-starter/quickstart) works out of the box.

# Deploy and Host

Deploy Medusa v2 on Railway in one click. The template provisions four services — `medusa-server` (API + admin, public domain, port 9000), `medusa-worker` (background jobs, private), `Postgres`, and `Redis` — with all environment variables, service references, generated secrets (`JWT_SECRET`, `COOKIE_SECRET`, `MEDUSA_ADMIN_PASSWORD`), healthchecks (`/health`), and restart policies pre-configured. Both Medusa services build from a public GitHub repo you can fork and customize (`src/api`, `src/modules`, `src/subscribers`, `src/workflows`).

## About Hosting

Medusa v2 is a Node.js (TypeScript) headless commerce backend. Production deployments split it into two processes from the same image: a **server** (`MEDUSA_WORKER_MODE=server`) that serves the Store/Admin APIs and the admin dashboard, and a **worker** (`MEDUSA_WORKER_MODE=worker`) that processes background events. The split only works because both share the same **Redis** event bus, workflow engine, cache, and lock modules — all wired for you. **Postgres** holds commerce data. Scale the worker independently (Railway → medusa-worker → Settings → Replicas); each replica joins the same BullMQ queues. Expect roughly **$15–30/month** total for a small store (server ~1 GB, worker 512 MB–1 GB, Postgres ~1 GB, Redis 256 MB). Medusa is MIT-licensed with no per-sale fees.

## Why Deploy

- **The official topology, pre-wired**: server + worker over the Redis event bus — not the single-container "shared" mode most templates ship, and not v1 (end-of-life).
- **Nothing to configure at deploy time**: references (`${{Postgres.DATABASE_URL}}`, `${{Redis.REDIS_URL}}`), secrets, CORS, and the admin backend URL are all expressions — deploys are unattended-safe.
- **Migrations run on boot, before serving**, and are idempotent — redeploys and restarts never corrupt schema state; the worker never races the schema.
- **Never locked out of your admin**: a user is bootstrapped from `MEDUSA_ADMIN_PASSWORD` on first boot, and the bootstrap is a no-op afterwards (change credentials from the dashboard).
- **Railway Redis IPv6 gotcha solved**: `family=0` is appended to the Redis URL automatically, so the event bus connects on the first try.
- **Pinned, maintained, documented**: Medusa `2.20.1` with a documented upgrade path, and a README that covers scaling, storefront connection, and troubleshooting.

## Common Use Cases

- Launching a self-hosted storefront (Shopify alternative) with full API control and no per-sale fees
- Headless commerce backends for Next.js/Remix/Expo storefronts using the official Medusa starters
- B2B and multi-region commerce needing custom workflows, price lists, or tax providers
- Learning and extending Medusa v2 (custom modules, subscribers, workflows) on infrastructure that mirrors production

## Dependencies for

### Deployment Dependencies

- A Railway account (Hobby plan or trial is enough)
- None of the usual setup: Postgres and Redis are provisioned by the template, secrets are generated at deploy time, and no external services (S3, SMTP, Stripe, etc.) are required for boot — add them later as Medusa modules when you need them
- Storefronts are optional and separate: connect the official Next.js starter afterwards and allow its origin in `STORE_CORS` / `AUTH_CORS`

## Troubleshooting

- **Stuck at "Creating server"** — you are on Medusa 2.17.0, which shipped the [`event-bus-redis` startup hang](https://github.com/medusajs/medusa/issues/15835) (fixed in 2.17.1). This template pins 2.20.1; if you bumped versions, move to ≥2.17.1.
- **Migrations failed at boot** — check Postgres is running and `DATABASE_URL` resolves; logs must show `migrations complete` before `starting Medusa...`.
- **Worker idle** — verify `medusa-worker` is running and references the same `Redis.REDIS_URL` as the server; create a product in the admin and watch the worker log for the event.
- **Locked out of `/app`** — the bootstrap only creates the user if it does not exist. Reset via the "Forgot password" flow, or delete the user row and restart `medusa-server` to re-run the bootstrap with a fresh `MEDUSA_ADMIN_PASSWORD`.
