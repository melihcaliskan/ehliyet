import type { FastifyInstance } from 'fastify';
import { and, asc, desc, eq, gte } from 'drizzle-orm';
import { appointments, exams } from '../db/schema.ts';

const DAY = 86_400_000;

/**
 * Uygulama içi bildirim akışı. Şimdilik kullanıcının verisinden türetilir;
 * push bildirimleri (APNs) eklendiğinde aynı içerik oradan da gönderilebilir.
 */
export async function notificationRoutes(app: FastifyInstance) {
  const { db } = app;

  app.get('/', { preHandler: app.authenticate }, async (req) => {
    const now = new Date();
    const [upcoming, lastExam] = await Promise.all([
      db
        .select()
        .from(appointments)
        .where(and(eq(appointments.userId, req.userId), gte(appointments.startsAt, now.toISOString().slice(0, 10))))
        .orderBy(asc(appointments.startsAt))
        .limit(3),
      db.query.exams.findFirst({ where: eq(exams.userId, req.userId), orderBy: desc(exams.startedAt) }),
    ]);

    type Item = { id: string; kind: 'appointment' | 'streak' | 'exam_result'; icon: string; color: string; title: string; body: string; date: string };
    const items: Item[] = [];

    for (const a of upcoming) {
      const days = Math.ceil((new Date(a.startsAt).getTime() - now.getTime()) / DAY);
      if (days > 30) continue;
      items.push({
        id: `appt-${a.id}`, kind: 'appointment', icon: 'calendar', color: '#D70015',
        title: `${a.title} yaklaşıyor`,
        body: days <= 0 ? 'Sınavın bugün. Başarılar!' : `Randevuna ${days} gün kaldı.`,
        date: now.toISOString(),
      });
    }

    const idleDays = lastExam ? Math.floor((now.getTime() - lastExam.startedAt.getTime()) / DAY) : null;
    if (idleDays === null || idleDays >= 1) {
      items.push({
        id: 'streak', kind: 'streak', icon: 'flame.fill', color: '#C93400',
        title: 'Seriyi bozma!',
        body: idleDays === null ? 'İlk deneme sınavını çözerek başla.' : 'Bugün henüz soru çözmedin.',
        date: now.toISOString(),
      });
    }

    if (lastExam?.finishedAt && now.getTime() - lastExam.finishedAt.getTime() < 7 * DAY) {
      const total = lastExam.questionIds.length;
      const score = total ? Math.round(((lastExam.correct ?? 0) / total) * 100) : 0;
      items.push({
        id: `exam-${lastExam.id}`, kind: 'exam_result', icon: 'checkmark.seal.fill', color: '#248A3D',
        title: 'Son deneme sonucun',
        body: `${score} puan aldın. ${score >= 70 ? 'Geçme notunun üzerindesin.' : 'Yanlışlarını tekrar etmeyi unutma.'}`,
        date: lastExam.finishedAt.toISOString(),
      });
    }

    return { notifications: items };
  });
}
