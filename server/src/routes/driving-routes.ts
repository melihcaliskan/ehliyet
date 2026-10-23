import type { FastifyInstance } from 'fastify';
import { and, asc, eq } from 'drizzle-orm';
import { z } from 'zod';
import { examRoutes } from '../db/schema.ts';
import { getEntitlements } from '../lib/entitlements.ts';

/** Direksiyon sınav güzergahları. Premium güzergahların harita ve kontrol noktaları kilitlidir. */
export async function drivingRoutes(app: FastifyInstance) {
  const { db } = app;

  app.get('/cities', async () => {
    const rows = await db
      .selectDistinct({ city: examRoutes.city, district: examRoutes.district })
      .from(examRoutes)
      .orderBy(asc(examRoutes.city), asc(examRoutes.district));
    const cities = new Map<string, string[]>();
    for (const r of rows) cities.set(r.city, [...(cities.get(r.city) ?? []), r.district]);
    return { cities: [...cities].map(([name, districts]) => ({ name, districts })) };
  });

  app.get('/', { preHandler: app.optionalAuth }, async (req) => {
    const q = z.object({ city: z.string().optional(), district: z.string().optional() }).parse(req.query);
    const [rows, ent] = await Promise.all([
      db
        .select()
        .from(examRoutes)
        .where(and(q.city ? eq(examRoutes.city, q.city) : undefined, q.district ? eq(examRoutes.district, q.district) : undefined))
        .orderBy(asc(examRoutes.city), asc(examRoutes.district)),
      req.userId ? getEntitlements(db, req.userId) : null,
    ]);
    const unlocked = ent?.scopes.includes('routes') ?? false;

    return {
      routes: rows.map((r) => {
        const locked = r.isPremium && !unlocked;
        return {
          id: r.id,
          city: r.city,
          district: r.district,
          name: r.name,
          distanceKm: r.distanceKm,
          isPremium: r.isPremium,
          locked,
          // Kilitliyse yalnızca harita merkezini gönder (bulanık önizleme için)
          center: r.path[Math.floor(r.path.length / 2)] ?? null,
          path: locked ? [] : r.path,
          checkpoints: locked ? [] : r.checkpoints,
          checkpointCount: r.checkpoints.length,
          videoLessonId: r.videoLessonId,
        };
      }),
    };
  });
}
