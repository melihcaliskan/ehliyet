import type { FastifyInstance } from 'fastify';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { users } from '../db/schema.ts';
import { hashPassword, verifyAppleIdentityToken, verifyPassword } from '../lib/auth.ts';
import { getEntitlements } from '../lib/entitlements.ts';

const email = z.email().transform((e) => e.toLowerCase());
const registerBody = z.object({
  email,
  password: z.string().min(8, 'Şifre en az 8 karakter olmalı').max(128),
  name: z.string().trim().min(1).max(80).optional(),
});
const loginBody = z.object({ email, password: z.string() });
const appleBody = z.object({
  identityToken: z.string(),
  // Apple adı yalnızca ilk girişte istemciye verir
  name: z.string().trim().max(80).optional(),
});
const refreshBody = z.object({ refreshToken: z.string() });

export async function authRoutes(app: FastifyInstance) {
  const { db, tokens } = app;
  const strict = { config: { rateLimit: { max: 10, timeWindow: '1 minute' } } };

  const publicUser = async (userId: string) => {
    const user = await db.query.users.findFirst({ where: eq(users.id, userId) });
    if (!user) return null;
    return {
      id: user.id, // iOS tarafında Product.PurchaseOption.appAccountToken(UUID) olarak gönderilir
      email: user.email,
      name: user.name,
      createdAt: user.createdAt.toISOString(),
      entitlements: await getEntitlements(db, userId),
    };
  };

  const session = async (userId: string) => ({ ...(await tokens.issuePair(userId)), user: await publicUser(userId) });

  app.post('/register', strict, async (req, reply) => {
    const body = registerBody.parse(req.body);
    const exists = await db.query.users.findFirst({ where: eq(users.email, body.email), columns: { id: true } });
    if (exists) return reply.code(409).send({ error: 'email_taken', message: 'Bu e-posta zaten kayıtlı' });

    const [user] = await db
      .insert(users)
      .values({ email: body.email, passwordHash: await hashPassword(body.password), name: body.name })
      .returning({ id: users.id });
    return reply.code(201).send(await session(user!.id));
  });

  app.post('/login', strict, async (req, reply) => {
    const body = loginBody.parse(req.body);
    const user = await db.query.users.findFirst({ where: eq(users.email, body.email) });
    const ok = user?.passwordHash ? await verifyPassword(body.password, user.passwordHash) : false;
    if (!user || !ok) return reply.code(401).send({ error: 'invalid_credentials', message: 'E-posta veya şifre hatalı' });
    return session(user.id);
  });

  app.post('/apple', strict, async (req, reply) => {
    const body = appleBody.parse(req.body);
    let identity;
    try {
      identity = await verifyAppleIdentityToken(body.identityToken, app.config.APPLE_BUNDLE_ID);
    } catch {
      return reply.code(401).send({ error: 'invalid_apple_token', message: 'Apple ile giriş doğrulanamadı' });
    }
    const appleEmail = identity.email?.toLowerCase();

    let user = await db.query.users.findFirst({ where: eq(users.appleSub, identity.sub), columns: { id: true } });
    if (!user && appleEmail) {
      // Aynı e-postayla daha önce kayıt olunmuşsa hesapları birleştir
      user = await db.query.users.findFirst({ where: eq(users.email, appleEmail), columns: { id: true } });
      if (user) await db.update(users).set({ appleSub: identity.sub }).where(eq(users.id, user.id));
    }
    if (!user) {
      [user] = await db
        .insert(users)
        .values({ email: appleEmail, appleSub: identity.sub, name: body.name })
        .returning({ id: users.id });
    }
    return session(user!.id);
  });

  app.post('/refresh', strict, async (req, reply) => {
    const { refreshToken } = refreshBody.parse(req.body);
    const rotated = await tokens.rotate(refreshToken);
    if (!rotated) return reply.code(401).send({ error: 'invalid_refresh', message: 'Oturum süresi doldu' });
    return { accessToken: await tokens.signAccess(rotated.userId), refreshToken: rotated.refreshToken };
  });

  app.post('/logout', async (req, reply) => {
    const { refreshToken } = refreshBody.parse(req.body);
    await tokens.revoke(refreshToken);
    return reply.code(204).send();
  });

  app.get('/me', { preHandler: app.authenticate }, async (req, reply) => {
    const user = await publicUser(req.userId);
    if (!user) return reply.code(404).send({ error: 'not_found' });
    return user;
  });

  // App Store yönergesi: uygulama içinden hesap silme zorunlu
  app.delete('/me', { preHandler: app.authenticate }, async (req, reply) => {
    await tokens.revokeAllForUser(req.userId);
    await db.delete(users).where(eq(users.id, req.userId));
    return reply.code(204).send();
  });
}
