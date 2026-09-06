import { loadEnv, defineConfig } from '@medusajs/framework/utils'

loadEnv(process.env.NODE_ENV || 'development', process.cwd())

/**
 * Railway's internal Redis proxy resolves to an IPv6 address. ioredis dials
 * IPv6 first and can silently hang when the host only answers on IPv4.
 * Appending `family=0` makes Node try both families (Happy Eyeballs), which
 * is the reliable default on Railway. Idempotent: existing `family=` wins.
 */
const normalizeRedisUrl = (url?: string): string | undefined => {
  if (!url) return url
  if (/([?&])family=/.test(url)) return url
  return url + (url.includes('?') ? '&' : '?') + 'family=0'
}

const redisUrl = normalizeRedisUrl(process.env.REDIS_URL)

// Production modules (event bus, workflow engine, cache, locks) all run on
// Redis so that a `server` deployment and a `worker` deployment share events
// and state. Without REDIS_URL (local dev) Medusa falls back to the in-memory
// defaults, so `npm run dev` works with no extra services.
const redisModules = redisUrl
  ? [
      {
        resolve: '@medusajs/medusa/event-bus-redis',
        options: { redisUrl },
      },
      {
        resolve: '@medusajs/medusa/workflow-engine-redis',
        options: {
          redis: { redisUrl },
        },
      },
      {
        resolve: '@medusajs/medusa/caching',
        options: {
          providers: [
            {
              resolve: '@medusajs/caching-redis',
              id: 'caching-redis',
              is_default: true,
              options: { redisUrl },
            },
          ],
        },
      },
      {
        resolve: '@medusajs/medusa/locking',
        options: {
          providers: [
            {
              resolve: '@medusajs/medusa/locking-redis',
              id: 'locking-redis',
              is_default: true,
              options: { redisUrl },
            },
          ],
        },
      },
    ]
  : []

module.exports = defineConfig({
  projectConfig: {
    databaseUrl: process.env.DATABASE_URL,
    redisUrl,
    workerMode: process.env.MEDUSA_WORKER_MODE as 'shared' | 'server' | 'worker',
    http: {
      storeCors: process.env.STORE_CORS!,
      adminCors: process.env.ADMIN_CORS!,
      authCors: process.env.AUTH_CORS!,
      jwtSecret: process.env.JWT_SECRET,
      cookieSecret: process.env.COOKIE_SECRET,
    },
  },
  admin: {
    disable: process.env.DISABLE_MEDUSA_ADMIN === 'true',
    backendUrl: process.env.MEDUSA_BACKEND_URL || undefined,
  },
  modules: redisModules,
})
