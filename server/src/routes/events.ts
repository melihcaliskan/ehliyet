import type { FastifyInstance } from 'fastify';
import { eq } from 'drizzle-orm';
import { z } from 'zod';
import { events, users } from '../db/schema.ts';

const prop = z.union([z.string().max(200), z.number(), z.boolean(), z.null()]);
const batchBody = z.object({
  deviceId: z.string().min(8).max(64),
  sessionId: z.string().min(8).max(64),
  appVersion: z.string().max(20).optional(),
  events: z
    .array(
      z.object({
        name: z.string().regex(/^[a-z][a-z0-9_.]{1,48}$/, 'olay adı snake_case olmalı'),
        props: z.record(z.string().max(40), prop).optional(),
        at: z.iso.datetime({ offset: true }),
      }),
    )
    .min(1)
    .max(100),
});

/**
 * Uygulama olaylarını toplu alır. Oturum açmadan önceki olaylar deviceId ile tutulur;
 * kullanıcı giriş yapınca aynı cihazın sonraki olayları kullanıcıya bağlanır.
 * Kişisel veri (e-posta, isim vb.) olay özelliklerine yazılmamalıdır.
 */
export async function eventRoutes(app: FastifyInstance) {
  const { db } = app;

  app.post('/', { preHandler: app.optionalAuth, config: { rateLimit: { max: 60, timeWindow: '1 minute' } } }, async (req, reply) => {
    const body = batchBody.parse(req.body);
    const now = Date.now();
    const rows = body.events.map((e) => {
      // Cihaz saati bozuksa sunucu zamanına sabitle
      const at = Date.parse(e.at);
      return {
        userId: req.userId || null,
        deviceId: body.deviceId,
        sessionId: body.sessionId,
        name: e.name,
        props: e.props ?? null,
        at: new Date(Math.abs(at - now) > 7 * 86_400_000 ? now : at),
        appVersion: body.appVersion ?? null,
      };
    });
    await db.insert(events).values(rows);
    if (req.userId) await db.update(users).set({ lastSeenAt: new Date() }).where(eq(users.id, req.userId));
    return reply.code(202).send({ accepted: rows.length });
  });
}
