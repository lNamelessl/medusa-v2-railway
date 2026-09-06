# --- Build stage: full toolchain, compiles backend + admin -------------------
FROM node:22-alpine AS build
WORKDIR /app
# libc6-compat: glibc compatibility for native build tooling (swc/esbuild) on musl
RUN apk add --no-cache libc6-compat

COPY package.json package-lock.json* ./
RUN npm ci --no-audit --no-fund || npm install --no-audit --no-fund

COPY . .
# The admin dashboard is compiled into the image unless DISABLE_MEDUSA_ADMIN=true
# is set at build time. One image serves both medusa-server and medusa-worker;
# the worker disables the admin at runtime via the same variable.
RUN npm run build

# --- Runtime stage: production output only -----------------------------------
FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production \
    PORT=9000

COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh && mkdir -p /app/.medusa

# medusa build outputs the production app to .medusa/server (plus the admin
# bundle under public/admin). Dependencies for the output are installed NOW,
# at build time, so a container restart / rescale never needs the network.
COPY --from=build /app/.medusa/server /app/.medusa/server
RUN cd /app/.medusa/server \
  && (npm ci --omit=dev --no-audit --no-fund || npm install --omit=dev --no-audit --no-fund) \
  && npm cache clean --force

EXPOSE 9000
# start.sh: (optionally) medusa db:migrate, bootstrap admin user, then serve.
# The same image + entrypoint runs in server and worker mode; behavior is
# driven by MEDUSA_WORKER_MODE / MIGRATE_ON_BOOT env vars.
CMD ["sh", "/app/start.sh"]
