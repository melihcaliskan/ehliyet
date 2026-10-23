import type { FastifyInstance } from 'fastify';
import { and, asc, eq } from 'drizzle-orm';
import { z } from 'zod';
import { lessonProgress, lessons } from '../db/schema.ts';
import { getEntitlements } from '../lib/entitlements.ts';
import type { VideoStorage } from '../lib/storage.ts';

const progressBody = z.object({ positionSec: z.number().int().min(0), completed: z.boolean().optional() });

export async function lessonRoutes(app: FastifyInstance, opts: { storage: VideoStorage | null }) {
  const { db } = app;
  const { storage } = opts;

  const videoFor = async (l: typeof lessons.$inferSelect) => {
    if (l.videoKey && storage) return storage.signedUrl(l.videoKey);
    return l.videoUrl ?? null;
  };

  const canWatch = async (userId: string) => (userId ? (await getEntitlements(db, userId)).scopes.includes('videos') : false);

  /** Oturum opsiyonel: misafirler de listeyi görür, kilitli derslerin video adresi gönderilmez */
  app.get('/', { preHandler: app.optionalAuth }, async (req) => {
    const { kind } = z.object({ kind: z.enum(['theory', 'driving']).optional() }).parse(req.query);
    const [rows, unlocked, progress] = await Promise.all([
      db.select().from(lessons).where(kind ? eq(lessons.kind, kind) : undefined).orderBy(asc(lessons.kind), asc(lessons.sort)),
      canWatch(req.userId),
      req.userId ? db.select().from(lessonProgress).where(eq(lessonProgress.userId, req.userId)) : Promise.resolve([]),
    ]);
    const byLesson = new Map(progress.map((p) => [p.lessonId, p]));

    const items = await Promise.all(rows.map(async (l) => {
      const locked = l.isPremium && !unlocked;
      const p = byLesson.get(l.id);
      return {
        id: l.id,
        kind: l.kind,
        chapter: l.chapter,
        title: l.title,
        minutes: l.minutes,
        isPremium: l.isPremium,
        locked,
        videoUrl: locked ? null : await videoFor(l),
        positionSec: p?.positionSec ?? 0,
        completed: p?.completed ?? false,
      };
    }));

    // "Kaldığın yer": en son izlenen, bitmemiş ders
    const resume = [...progress]
      .filter((p) => !p.completed && p.positionSec > 0)
      .sort((a, b) => b.updatedAt.getTime() - a.updatedAt.getTime())[0];

    return { lessons: items, resumeLessonId: resume?.lessonId ?? null };
  });

  app.put('/:id/progress', { preHandler: app.authenticate }, async (req, reply) => {
    const { id } = z.object({ id: z.string() }).parse(req.params);
    const body = progressBody.parse(req.body);
    const lesson = await db.query.lessons.findFirst({ where: eq(lessons.id, id) });
    if (!lesson) return reply.code(404).send({ error: 'not_found' });
    if (lesson.isPremium && !(await canWatch(req.userId))) {
      return reply.code(402).send({ error: 'premium_required', message: "Bu ders Premium'a dahil" });
    }

    // %90'ı izlenen ders tamamlandı sayılır; tamamlanmış ders geri "bitmedi"ye dönmez
    const completed = body.completed ?? body.positionSec >= lesson.minutes * 60 * 0.9;
    await db
      .insert(lessonProgress)
      .values({ userId: req.userId, lessonId: id, positionSec: body.positionSec, completed })
      .onConflictDoUpdate({
        target: [lessonProgress.userId, lessonProgress.lessonId],
        set: { positionSec: body.positionSec, completed: completed ? true : undefined, updatedAt: new Date() },
      });
    const row = await db.query.lessonProgress.findFirst({
      where: and(eq(lessonProgress.userId, req.userId), eq(lessonProgress.lessonId, id)),
    });
    return { lessonId: id, positionSec: row!.positionSec, completed: row!.completed };
  });
}
