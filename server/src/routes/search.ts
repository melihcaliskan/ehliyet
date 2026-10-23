import type { FastifyInstance } from 'fastify';
import { asc } from 'drizzle-orm';
import { z } from 'zod';
import { lessons, questions, topics } from '../db/schema.ts';

// Türkçe büyük/küçük harf ve aksan farkını yok sayan sade normalizasyon ("İLK yardım" ≈ "ilk yardim")
const norm = (s: string) =>
  s.toLocaleLowerCase('tr').normalize('NFD').replace(/\p{Diacritic}/gu, '').replace(/ı/g, 'i');

/**
 * Soru ve ders araması. İçerik küçük olduğu sürece bellekte filtrelenir;
 * soru bankası büyüdüğünde Turso'nun FTS5 tam metin aramasına taşınmalı.
 */
export async function searchRoutes(app: FastifyInstance) {
  const { db } = app;

  app.get('/', async (req) => {
    const { q } = z.object({ q: z.string().trim().min(2).max(80) }).parse(req.query);
    const needle = norm(q);
    const [qs, ls, ts] = await Promise.all([
      db.select().from(questions),
      db.select().from(lessons).orderBy(asc(lessons.kind), asc(lessons.sort)),
      db.select().from(topics),
    ]);
    const topicName = new Map(ts.map((t) => [t.id, t.name]));

    return {
      lessons: ls
        .filter((l) => norm(l.title).includes(needle) || norm(l.chapter).includes(needle))
        .slice(0, 10)
        .map((l) => ({ id: l.id, kind: l.kind, title: l.title, chapter: l.chapter, isPremium: l.isPremium })),
      questions: qs
        .filter((x) => norm(x.text).includes(needle) || norm(topicName.get(x.topicId) ?? '').includes(needle))
        .slice(0, 20)
        .map((x) => ({ id: x.id, topicId: x.topicId, topic: topicName.get(x.topicId) ?? x.topicId, text: x.text })),
    };
  });
}
