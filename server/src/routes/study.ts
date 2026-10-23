import type { FastifyInstance } from 'fastify';
import { and, asc, count, desc, eq, gte, inArray, isNotNull } from 'drizzle-orm';
import { z } from 'zod';
import type { DB } from '../db/index.ts';
import { answers, exams, questionReports, questions, topics } from '../db/schema.ts';
import { getEntitlements } from '../lib/entitlements.ts';

export const FREE_MOCK_EXAMS = 3;
const MOCK_SIZE = 50;
const MOCK_TIME_SEC = 45 * 60;
const TOPIC_SIZE = 20;
const PASS_SCORE = 70;

const DAILY_SIZE = 10;
const MOCK_KINDS = ['mock', 'real'] as const;
/** e-sınavdaki konu ağırlıkları (50 soruda) */
const EXAM_WEIGHTS: Record<string, number> = { trafik: 23, ilkyardim: 12, motor: 9, adab: 6 };

/** Gün sınırı Türkiye saatine göre */
export const dayKey = (d: Date) => new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Istanbul' }).format(d);

const startBody = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('mock') }),
  z.object({ kind: z.literal('real') }),
  z.object({ kind: z.literal('daily') }),
  z.object({ kind: z.literal('topic'), topicId: z.string() }),
  z.object({ kind: z.literal('wrongs') }),
]);
const answerBody = z.object({ questionId: z.string(), choice: z.number().int().min(0).max(5) });
const finishBody = z.object({ durationSec: z.number().int().min(0).max(6 * 3600) });

type QuestionRow = typeof questions.$inferSelect;

const shuffle = <T>(xs: T[]) => {
  const a = [...xs];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j]!, a[i]!];
  }
  return a;
};

/** Her sorunun son cevabı yanlışsa "yanlış" sayılır; doğru cevaplanınca listeden düşer. */
async function latestAnswers(db: DB, userId: string) {
  const rows = await db
    .select({ questionId: answers.questionId, correct: answers.correct })
    .from(answers)
    .where(eq(answers.userId, userId))
    .orderBy(asc(answers.answeredAt));
  const latest = new Map<string, boolean>();
  for (const r of rows) latest.set(r.questionId, r.correct);
  return latest;
}

async function mockExamsUsed(db: DB, userId: string) {
  const [row] = await db.select({ n: count() }).from(exams).where(and(eq(exams.userId, userId), inArray(exams.kind, [...MOCK_KINDS])));
  return row?.n ?? 0;
}

export async function studyRoutes(app: FastifyInstance) {
  const { db } = app;

  const topicNames = async () => new Map((await db.select().from(topics)).map((t) => [t.id, t.name]));
  /** Gerçek sınav modunda doğru cevap ve açıklama sınav bitene kadar gönderilmez */
  const toQuestion = (q: QuestionRow, names: Map<string, string>, hideAnswer = false) => ({
    id: q.id,
    topicId: q.topicId,
    topic: names.get(q.topicId) ?? q.topicId,
    text: q.text,
    options: q.options,
    answer: hideAnswer ? null : q.answer,
    explanation: hideAnswer ? null : q.explanation,
    image: q.image ?? null,
  });

  app.get('/topics', async () => {
    const rows = await db
      .select({ id: topics.id, name: topics.name, icon: topics.icon, color: topics.color, questionCount: count(questions.id) })
      .from(topics)
      .leftJoin(questions, eq(questions.topicId, topics.id))
      .groupBy(topics.id)
      .orderBy(asc(topics.sort));
    return { topics: rows };
  });

  app.register(async (priv) => {
    priv.addHook('preHandler', app.authenticate);

    /** Konu bazında ilerleme, yanlış sayısı ve deneme hakkı — ana sayfa için tek istek */
    priv.get('/progress', async (req) => {
      const [all, latest, ent, used] = await Promise.all([
        db.select({ id: questions.id, topicId: questions.topicId }).from(questions),
        latestAnswers(db, req.userId),
        getEntitlements(db, req.userId),
        mockExamsUsed(db, req.userId),
      ]);
      const byTopic = new Map<string, { total: number; correct: number }>();
      for (const q of all) {
        const t = byTopic.get(q.topicId) ?? { total: 0, correct: 0 };
        t.total++;
        if (latest.get(q.id) === true) t.correct++;
        byTopic.set(q.topicId, t);
      }
      return {
        topics: [...byTopic].map(([topicId, t]) => ({ topicId, ...t, progress: t.total ? t.correct / t.total : 0 })),
        wrongCount: [...latest.values()].filter((c) => !c).length,
        mockExams: { used: used, limit: ent.isPremium ? null : FREE_MOCK_EXAMS, remaining: ent.isPremium ? null : Math.max(0, FREE_MOCK_EXAMS - used) },
      };
    });

    priv.get('/wrong-answers', async (req) => {
      const latest = await latestAnswers(db, req.userId);
      const ids = [...latest].filter(([, c]) => !c).map(([id]) => id);
      if (!ids.length) return { questions: [] };
      const [rows, names] = await Promise.all([db.select().from(questions).where(inArray(questions.id, ids)), topicNames()]);
      return { questions: rows.map((q) => toQuestion(q, names)) };
    });

    priv.post('/exams', async (req, reply) => {
      const body = startBody.parse(req.body);
      const ent = await getEntitlements(db, req.userId);
      let pool: QuestionRow[];
      let timeLimitSec: number | null = null;

      if (body.kind === 'daily') {
        // Günün sınavı tektir: bugün başlatılmışsa aynısı döner
        const today = await db.query.exams.findFirst({
          where: and(eq(exams.userId, req.userId), eq(exams.kind, 'daily'), gte(exams.startedAt, startOfDay())),
          orderBy: desc(exams.startedAt),
        });
        const names = await topicNames();
        if (today) {
          const rows = await db.select().from(questions).where(inArray(questions.id, today.questionIds));
          const byId = new Map(rows.map((r) => [r.id, r]));
          const answered = await db.select({ questionId: answers.questionId, choice: answers.choice }).from(answers).where(eq(answers.examId, today.id));
          return reply.code(200).send({
            id: today.id, kind: 'daily', timeLimitSec: null, passScore: PASS_SCORE, finished: !!today.finishedAt,
            questions: today.questionIds.map((id) => byId.get(id)).filter(Boolean).map((q) => toQuestion(q!, names)),
            answered,
          });
        }
        pool = await dailyPool(db, req.userId);
      } else if (body.kind === 'mock' || body.kind === 'real') {
        if (!ent.isPremium && (await mockExamsUsed(db, req.userId)) >= FREE_MOCK_EXAMS) {
          return reply.code(402).send({ error: 'free_limit_reached', message: 'Ücretsiz deneme hakkın bitti' });
        }
        pool = await mockPool(db);
        timeLimitSec = MOCK_TIME_SEC;
      } else if (body.kind === 'topic') {
        pool = shuffle(await db.select().from(questions).where(and(eq(questions.topicId, body.topicId), eq(questions.active, true)))).slice(0, TOPIC_SIZE);
        if (!pool.length) return reply.code(404).send({ error: 'not_found', message: 'Bu konuda soru yok' });
      } else {
        if (!ent.isPremium) {
          return reply.code(402).send({ error: 'premium_required', message: "Yanlışlara özel test Premium'a dahil" });
        }
        const latest = await latestAnswers(db, req.userId);
        const ids = [...latest].filter(([, c]) => !c).map(([id]) => id);
        pool = ids.length ? shuffle(await db.select().from(questions).where(inArray(questions.id, ids))) : [];
        if (!pool.length) return reply.code(404).send({ error: 'no_wrong_answers', message: 'Tekrar edilecek yanlışın yok' });
      }

      const [exam] = await db
        .insert(exams)
        .values({ userId: req.userId, kind: body.kind, topicId: body.kind === 'topic' ? body.topicId : null, questionIds: pool.map((q) => q.id) })
        .returning();
      const names = await topicNames();
      return reply.code(201).send({
        id: exam!.id,
        kind: exam!.kind,
        timeLimitSec,
        passScore: PASS_SCORE,
        finished: false,
        questions: pool.map((q) => toQuestion(q, names, body.kind === 'real')),
        answered: [],
      });
    });

    const ownExam = async (userId: string, id: string) =>
      db.query.exams.findFirst({ where: and(eq(exams.id, id), eq(exams.userId, userId)) });

    /** Her cevap anında kaydedilir; sınav yarıda bırakılsa da ilerleme korunur */
    priv.post('/exams/:id/answers', async (req, reply) => {
      const { id } = z.object({ id: z.uuid() }).parse(req.params);
      const body = answerBody.parse(req.body);
      const exam = await ownExam(req.userId, id);
      if (!exam) return reply.code(404).send({ error: 'not_found' });
      if (exam.finishedAt) return reply.code(409).send({ error: 'exam_finished', message: 'Sınav bitti' });
      if (!exam.questionIds.includes(body.questionId)) return reply.code(400).send({ error: 'question_not_in_exam' });

      const already = await db.query.answers.findFirst({ where: and(eq(answers.examId, id), eq(answers.questionId, body.questionId)) });
      const q = await db.query.questions.findFirst({ where: eq(questions.id, body.questionId) });
      const correct = q!.answer === body.choice;

      if (exam.kind === 'real') {
        // Gerçek sınavda olduğu gibi cevap bitirene kadar değiştirilebilir ve sonuç gösterilmez
        if (already) await db.update(answers).set({ choice: body.choice, correct, answeredAt: new Date() }).where(eq(answers.id, already.id));
        else await db.insert(answers).values({ userId: req.userId, questionId: body.questionId, examId: id, choice: body.choice, correct });
        return { recorded: true };
      }
      if (already) return reply.code(409).send({ error: 'already_answered', message: 'Bu soru cevaplandı' });
      await db.insert(answers).values({ userId: req.userId, questionId: body.questionId, examId: id, choice: body.choice, correct });
      return { correct, answer: q!.answer };
    });

    priv.post('/exams/:id/finish', async (req, reply) => {
      const { id } = z.object({ id: z.uuid() }).parse(req.params);
      const { durationSec } = finishBody.parse(req.body);
      const exam = await ownExam(req.userId, id);
      if (!exam) return reply.code(404).send({ error: 'not_found' });

      if (!exam.finishedAt) {
        const rows = await db.select({ correct: answers.correct }).from(answers).where(eq(answers.examId, id));
        const correct = rows.filter((r) => r.correct).length;
        await db
          .update(exams)
          .set({ finishedAt: new Date(), correct, wrong: exam.questionIds.length - correct, durationSec })
          .where(eq(exams.id, id));
      }
      const done = (await ownExam(req.userId, id))!;
      return summary(done);
    });

    /** Biten sınavın soru soru dökümü (gerçek sınav modunda cevaplar burada açılır) */
    priv.get('/exams/:id/review', async (req, reply) => {
      const { id } = z.object({ id: z.uuid() }).parse(req.params);
      const exam = await ownExam(req.userId, id);
      if (!exam) return reply.code(404).send({ error: 'not_found' });
      if (!exam.finishedAt) return reply.code(409).send({ error: 'exam_not_finished' });
      const [rows, given, names] = await Promise.all([
        db.select().from(questions).where(inArray(questions.id, exam.questionIds)),
        db.select({ questionId: answers.questionId, choice: answers.choice }).from(answers).where(eq(answers.examId, id)),
        topicNames(),
      ]);
      const byId = new Map(rows.map((r) => [r.id, r]));
      const choice = new Map(given.map((g) => [g.questionId, g.choice]));
      return {
        summary: summary(exam),
        items: exam.questionIds.flatMap((qid) => {
          const q = byId.get(qid);
          if (!q) return [];
          const c = choice.get(qid) ?? null;
          return [{ question: toQuestion(q, names), choice: c, correct: c === q.answer }];
        }),
      };
    });

    /** Günlük 10 soru ve seri durumu */
    priv.get('/daily', async (req) => {
      const [today, streak] = await Promise.all([
        db.query.exams.findFirst({
          where: and(eq(exams.userId, req.userId), eq(exams.kind, 'daily'), gte(exams.startedAt, startOfDay())),
          orderBy: desc(exams.startedAt),
        }),
        streakFor(db, req.userId),
      ]);
      return {
        date: dayKey(new Date()),
        size: DAILY_SIZE,
        started: !!today,
        completed: !!today?.finishedAt,
        correct: today?.correct ?? null,
        ...streak,
      };
    });

    /** Hazırlık skoru: son denemeler (%60) + e-sınav ağırlıklı konu kapsamı (%40) */
    priv.get('/readiness', async (req) => {
      const [recent, all, latest] = await Promise.all([
        db.select().from(exams)
          .where(and(eq(exams.userId, req.userId), inArray(exams.kind, [...MOCK_KINDS]), isNotNull(exams.finishedAt)))
          .orderBy(desc(exams.finishedAt)).limit(3),
        db.select({ id: questions.id, topicId: questions.topicId }).from(questions).where(eq(questions.active, true)),
        latestAnswers(db, req.userId),
      ]);

      const perTopic = new Map<string, { total: number; correct: number }>();
      for (const q of all) {
        const t = perTopic.get(q.topicId) ?? { total: 0, correct: 0 };
        t.total++;
        if (latest.get(q.id) === true) t.correct++;
        perTopic.set(q.topicId, t);
      }
      const weightSum = Object.values(EXAM_WEIGHTS).reduce((a, b) => a + b, 0);
      let coverage = 0;
      for (const [topicId, w] of Object.entries(EXAM_WEIGHTS)) {
        const t = perTopic.get(topicId);
        coverage += (t && t.total ? t.correct / t.total : 0) * (w / weightSum);
      }
      const examAvg = recent.length ? recent.map(summary).reduce((a, e) => a + e.score, 0) / recent.length : null;
      const score = Math.round(examAvg === null ? coverage * 100 * 0.6 : examAvg * 0.6 + coverage * 100 * 0.4);

      const names = await topicNames();
      const weakest = [...perTopic]
        .map(([topicId, t]) => ({ topicId, name: names.get(topicId) ?? topicId, progress: t.total ? t.correct / t.total : 0 }))
        .sort((a, b) => a.progress - b.progress)[0] ?? null;

      const level = score >= 80 ? 'high' : score >= 60 ? 'medium' : 'low';
      const advice =
        recent.length === 0 ? 'Skorunun güvenilir olması için en az bir deneme sınavı çöz.'
        : level === 'high' ? 'Sınava hazır görünüyorsun. Gerçek sınav moduyla son provanı yap.'
        : weakest ? `${weakest.name} konusuna ağırlık ver; skorunu en hızlı bu konu yükseltir.`
        : 'Her gün 10 soru çözerek skorunu yükselt.';

      return {
        score, level, advice,
        examAverage: examAvg === null ? null : Math.round(examAvg),
        examsCounted: recent.length,
        coverage: Math.round(coverage * 100),
        weakestTopic: weakest,
      };
    });

    priv.post('/questions/:id/report', async (req, reply) => {
      const { id } = z.object({ id: z.string() }).parse(req.params);
      const { message } = z.object({ message: z.string().trim().min(3).max(500) }).parse(req.body);
      const q = await db.query.questions.findFirst({ where: eq(questions.id, id), columns: { id: true } });
      if (!q) return reply.code(404).send({ error: 'not_found' });
      await db.insert(questionReports).values({ questionId: id, userId: req.userId, message });
      return reply.code(201).send({ ok: true });
    });

    priv.get('/exams', async (req) => {
      const rows = await db
        .select()
        .from(exams)
        .where(and(eq(exams.userId, req.userId), isNotNull(exams.finishedAt)))
        .orderBy(desc(exams.finishedAt))
        .limit(50);
      return { exams: rows.map(summary) };
    });
  });
}

const startOfDay = () => new Date(`${dayKey(new Date())}T00:00:00+03:00`);

/** e-sınav dağılımına göre konu ağırlıklı 50 soru */
async function mockPool(db: DB) {
  const all = await db.select().from(questions).where(eq(questions.active, true));
  const picked: QuestionRow[] = [];
  for (const [topicId, n] of Object.entries(EXAM_WEIGHTS)) {
    picked.push(...shuffle(all.filter((q) => q.topicId === topicId)).slice(0, n));
  }
  // Bir konuda yeterli soru yoksa kalan yer diğer sorularla doldurulur
  const rest = shuffle(all.filter((q) => !picked.includes(q)));
  return shuffle([...picked, ...rest].slice(0, MOCK_SIZE));
}

/**
 * Günlük 10 soru: önce tekrar zamanı gelen yanlışlar (aralıklı tekrar: 1, 3, 7 gün),
 * sonra hiç çözülmemiş sorular, sonra rastgele.
 */
async function dailyPool(db: DB, userId: string) {
  const all = await db.select().from(questions).where(eq(questions.active, true));
  const history = await db
    .select({ questionId: answers.questionId, correct: answers.correct, at: answers.answeredAt })
    .from(answers).where(eq(answers.userId, userId)).orderBy(asc(answers.answeredAt));

  const state = new Map<string, { correct: boolean; at: Date; streak: number }>();
  for (const h of history) {
    const prev = state.get(h.questionId);
    state.set(h.questionId, { correct: h.correct, at: h.at, streak: h.correct ? (prev?.streak ?? 0) + 1 : 0 });
  }
  const INTERVALS = [1, 3, 7];
  const now = Date.now();
  const due = all.filter((q) => {
    const s = state.get(q.id);
    if (!s) return false;
    if (!s.correct) return now - s.at.getTime() >= 20 * 3600_000;
    const days = INTERVALS[s.streak - 1];
    return days !== undefined && now - s.at.getTime() >= days * 86_400_000;
  });
  const fresh = all.filter((q) => !state.has(q.id));
  const picked = [...shuffle(due), ...shuffle(fresh)].slice(0, DAILY_SIZE);
  const rest = shuffle(all.filter((q) => !picked.includes(q)));
  return [...picked, ...rest].slice(0, DAILY_SIZE);
}

/** Seri: üst üste günlük soruların bitirildiği gün sayısı (bugün henüz yapılmadıysa dünden geriye sayılır) */
async function streakFor(db: DB, userId: string) {
  const rows = await db
    .select({ at: exams.finishedAt })
    .from(exams)
    .where(and(eq(exams.userId, userId), eq(exams.kind, 'daily'), isNotNull(exams.finishedAt)));
  const days = new Set(rows.map((r) => dayKey(r.at!)));
  let streak = 0;
  const cursor = new Date();
  if (!days.has(dayKey(cursor))) cursor.setTime(cursor.getTime() - 86_400_000);
  while (days.has(dayKey(cursor))) {
    streak++;
    cursor.setTime(cursor.getTime() - 86_400_000);
  }
  return { streak, best: longestStreak([...days].sort()) };
}

function longestStreak(sortedDays: string[]) {
  let best = 0, run = 0, prev: number | null = null;
  for (const d of sortedDays) {
    const t = Date.parse(d);
    run = prev !== null && t - prev === 86_400_000 ? run + 1 : 1;
    best = Math.max(best, run);
    prev = t;
  }
  return best;
}

function summary(e: typeof exams.$inferSelect) {
  const total = e.questionIds.length;
  const correct = e.correct ?? 0;
  const score = total ? Math.round((correct / total) * 100) : 0;
  return {
    id: e.id,
    kind: e.kind,
    topicId: e.topicId,
    total,
    correct,
    wrong: e.wrong ?? total - correct,
    score,
    passed: score >= PASS_SCORE,
    durationSec: e.durationSec ?? 0,
    startedAt: e.startedAt.toISOString(),
    finishedAt: e.finishedAt?.toISOString() ?? null,
  };
}
