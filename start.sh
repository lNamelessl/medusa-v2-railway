#!/bin/sh
# Medusa v2 container entrypoint (server AND worker services share this image).
#
# Ordering is the whole point of this script:
#   1. migrations   (medusa db:migrate — idempotent, safe on every boot)
#   2. admin user   (bootstrap once; retries are no-ops when the user exists)
#   3. serve        (medusa start)
#
# Migrations run ONLY where they should: server/shared mode, or whenever
# MIGRATE_ON_BOOT=true is set explicitly. The worker service sets
# MIGRATE_ON_BOOT=false and lets the server own schema changes.
set -e

MODE="${MEDUSA_WORKER_MODE:-shared}"
cd /app/.medusa/server

echo "[start] worker mode: ${MODE}"

if [ "${MIGRATE_ON_BOOT:-true}" = "true" ] && [ "${MODE}" != "worker" ]; then
  echo "[start] running migrations (medusa db:migrate)..."
  npm run predeploy
  echo "[start] migrations complete"
fi

if [ "${MODE}" != "worker" ] \
   && [ -n "${MEDUSA_ADMIN_EMAIL:-}" ] \
   && [ -n "${MEDUSA_ADMIN_PASSWORD:-}" ]; then
  echo "[start] ensuring admin user ${MEDUSA_ADMIN_EMAIL} exists..."
  npx --no-install medusa user -e "${MEDUSA_ADMIN_EMAIL}" -p "${MEDUSA_ADMIN_PASSWORD}" \
    || echo "[start] admin user not created (probably already exists) — continuing"
fi

echo "[start] starting Medusa..."
exec npm run start
