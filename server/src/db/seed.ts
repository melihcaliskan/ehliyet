import { sql } from 'drizzle-orm';
import type { DB } from './index.ts';
import { examRoutes, examSessions, feeItems, lessons, questions, topics } from './schema.ts';
import { LESSONS, QUESTIONS, ROUTES, TOPICS } from './content.ts';
import { FEES } from './fees.ts';

// MTSK e-sınavı sabit günlerde değil, randevuyla haftanın her günü yapılır (MEB 2026 Sınav Uygulama Takvimi).
// Bu yüzden takvim tablosu yalnızca il/ülke geneli istisnai günler (bayram kapanışı vb.) için kullanılır.
const sessions: (typeof examSessions.$inferInsert)[] = [];

/** Seed özetini hesaplamak için tüm içerik */
export const seedContent = { FEES, sessions, TOPICS, QUESTIONS, LESSONS, ROUTES };

export async function seed(db: DB) {
  // Eski örnek kalemleri temizle, tarifeyi her açılışta güncel hâliyle yaz
  await db.run(sql`DELETE FROM fee_items WHERE id NOT LIKE '2026-%'`);
  await db.run(sql`DELETE FROM exam_sessions WHERE id IN ('es-2026-11-12', 'es-2026-11-26', 'dr-2026-11-27', 'es-2026-12-10')`);
  await db
    .insert(feeItems)
    .values(FEES)
    .onConflictDoUpdate({
      target: feeItems.id,
      set: { amountKurus: sql`excluded.amount_kurus`, title: sql`excluded.title`, isEstimate: sql`excluded.is_estimate`, source: sql`excluded.source` },
    });
  if (sessions.length) await db.insert(examSessions).values(sessions).onConflictDoNothing();
  await db.insert(topics).values(TOPICS).onConflictDoNothing();
  await db
    .insert(questions)
    .values(QUESTIONS)
    .onConflictDoUpdate({
      target: questions.id,
      set: { topicId: sql`excluded.topic_id`, text: sql`excluded.text`, options: sql`excluded.options`, answer: sql`excluded.answer`, explanation: sql`excluded.explanation`, image: sql`excluded.image` },
    });
  // İlk sürümdeki örnek sorular (q1…q10) cevaplanmamışsa kaldırılır
  await db.run(sql`DELETE FROM questions WHERE id GLOB 'q[0-9]*' AND id NOT IN (SELECT question_id FROM answers)`);
  await db
    .insert(lessons)
    .values(LESSONS)
    .onConflictDoUpdate({ target: lessons.id, set: { title: sql`excluded.title`, isPremium: sql`excluded.is_premium`, videoKey: sql`excluded.video_key` } });
  await db.run(sql`UPDATE lessons SET video_url = NULL WHERE video_url LIKE 'https://cdn.example.com/%'`);
  await db.insert(examRoutes).values(ROUTES).onConflictDoNothing();
}
