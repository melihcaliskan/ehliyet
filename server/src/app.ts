import Fastify, { type FastifyReply, type FastifyRequest } from 'fastify';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import { ZodError } from 'zod';
import type { Config } from './config.ts';
import { openDatabase, type DB } from './db/index.ts';
import { TokenService } from './lib/auth.ts';
import { createAppStoreVerifier, type AppStoreVerifier } from './lib/appstore.ts';
import { createVideoStorage, type VideoStorage } from './lib/storage.ts';
import { authRoutes } from './routes/auth.ts';
import { calendarRoutes } from './routes/calendar.ts';
import { feeRoutes } from './routes/fees.ts';
import { iapRoutes } from './routes/iap.ts';
import { studyRoutes } from './routes/study.ts';
import { lessonRoutes } from './routes/lessons.ts';
import { drivingRoutes } from './routes/driving-routes.ts';
import { notificationRoutes } from './routes/notifications.ts';
import { searchRoutes } from './routes/search.ts';
import { checklistRoutes } from './routes/checklist.ts';
import { eventRoutes } from './routes/events.ts';
import { adminRoutes } from './routes/admin.ts';
import { readFile } from 'node:fs/promises';
import { ruleRoutes } from './routes/rules.ts';

declare module 'fastify' {
  interface FastifyInstance {
    db: DB;
    config: Config;
    tokens: TokenService;
    authenticate: (req: FastifyRequest, reply: FastifyReply) => Promise<void>;
    /** Token varsa ve geçerliyse userId'yi doldurur, yoksa misafir olarak devam eder */
    optionalAuth: (req: FastifyRequest) => Promise<void>;
  }
  interface FastifyRequest {
    userId: string;
  }
}

export async function buildApp(config: Config, deps: { verifier?: AppStoreVerifier; storage?: VideoStorage | null } = {}) {
  const app = Fastify({
    logger: config.NODE_ENV === 'test' ? false : { level: 'info' },
  });

  const { db, close } = await openDatabase(config.DATABASE_URL, config.DATABASE_AUTH_TOKEN);
  app.decorate('db', db);
  app.decorate('config', config);
  app.decorate('tokens', new TokenService(config, db));
  app.decorateRequest('userId', '');
  app.addHook('onClose', async () => close());

  await app.register(cors);
  await app.register(rateLimit, { max: 120, timeWindow: '1 minute' });

  app.decorate('authenticate', async (req: FastifyRequest, reply: FastifyReply) => {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      return reply.code(401).send({ error: 'unauthorized', message: 'Oturum açmanız gerekiyor' });
    }
    try {
      req.userId = await app.tokens.verifyAccess(header.slice(7));
    } catch {
      return reply.code(401).send({ error: 'invalid_token', message: 'Oturum süresi doldu' });
    }
  });

  app.decorate('optionalAuth', async (req: FastifyRequest) => {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) return;
    try {
      req.userId = await app.tokens.verifyAccess(header.slice(7));
    } catch {
      // geçersiz token: misafir
    }
  });

  app.setErrorHandler((err, _req, reply) => {
    if (err instanceof ZodError) {
      return reply.code(400).send({ error: 'validation', issues: err.issues });
    }
    const e = err as { statusCode?: number; code?: string; message?: string };
    const status = e.statusCode ?? 500;
    if (status >= 500) app.log.error(err);
    return reply.code(status).send({
      error: status >= 500 ? 'internal' : (e.code ?? 'request'),
      message: status >= 500 ? 'Sunucu hatası' : e.message,
    });
  });

  app.get('/health', async () => ({ ok: true }));
  await app.register(authRoutes, { prefix: '/v1/auth' });
  await app.register(calendarRoutes, { prefix: '/v1/calendar' });
  await app.register(feeRoutes, { prefix: '/v1/fees' });
  await app.register(ruleRoutes, { prefix: '/v1/rules' });
  await app.register(studyRoutes, { prefix: '/v1/study' });
  await app.register(lessonRoutes, { prefix: '/v1/lessons', storage: deps.storage === undefined ? createVideoStorage(config) : deps.storage });
  await app.register(drivingRoutes, { prefix: '/v1/routes' });
  await app.register(notificationRoutes, { prefix: '/v1/notifications' });
  await app.register(searchRoutes, { prefix: '/v1/search' });
  await app.register(checklistRoutes, { prefix: '/v1/checklist' });
  await app.register(eventRoutes, { prefix: '/v1/events' });
  await app.register(adminRoutes, { prefix: '/v1/admin' });

  // App Store'un istediği gizlilik ve kullanım koşulları sayfaları
  for (const page of ['privacy', 'terms'] as const) {
    const file = new URL(`../legal/${page}.html`, import.meta.url);
    app.get(`/legal/${page}`, async (_req, reply) => {
      const html = await readFile(file, 'utf8').catch(() => null);
      if (!html) return reply.code(404).send({ error: 'not_found' });
      reply.header('Cache-Control', 'public, max-age=3600');
      return reply.type('text/html').send(html);
    });
  }

  // Yönetim paneli: tek sayfalık statik uygulama, verileri /v1/admin'den çeker
  const adminPage = new URL('../admin/index.html', import.meta.url);
  app.get('/admin', async (_req, reply) => {
    const html = await readFile(adminPage, 'utf8').catch(() => null);
    if (!html) return reply.code(404).send({ error: 'not_found', message: 'Yönetim paneli dosyası pakette yok' });
    reply.header('Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; connect-src 'self'");
    return reply.type('text/html').send(html);
  });
  await app.register(iapRoutes, { prefix: '/v1/iap', verifier: deps.verifier ?? createAppStoreVerifier(config) });

  return app;
}
