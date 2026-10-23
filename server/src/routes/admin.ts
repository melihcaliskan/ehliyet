import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { and, asc, count, desc, eq, gte, inArray, like, or } from 'drizzle-orm';
import { z } from 'zod';
import { events, exams, feeItems, purchases, questionReports, questions, topics, users } from '../db/schema.ts';
import { getEntitlements } from '../lib/entitlements.ts';
import { PRODUCTS } from '../lib/products.ts';
import { dayKey } from './study.ts';

const DAY = 86_400_000;

type EventRow = { userId: string | null; deviceId: string; sessionId: string; at: Date };

/** Olaylardan oturum süreleri: oturum içi ilk-son olay farkı (tek olaylı oturum 0 sn) */
function sessionsFrom(rows: EventRow[]) {
  const bySession = new Map<string, { userId: string | null; deviceId: string; start: number; end: number }>();
  for (const r of rows) {
    const t = r.at.getTime();
    const s = bySession.get(r.sessionId);
    if (!s) bySession.set(r.sessionId, { userId: r.userId, deviceId: r.deviceId, start: t, end: t });
    else {
      s.start = Math.min(s.start, t);
      s.end = Math.max(s.end, t);
      s.userId ??= r.userId;
    }
  }
  return [...bySession.values()].map((s) => ({ ...s, durationSec: Math.min(4 * 3600, Math.round((s.end - s.start) / 1000)) }));
}

const questionBody = z.object({
  topicId: z.string(),
  text: z.string().trim().min(5),
  options: z.array(z.string().trim().min(1)).min(2).max(5),
  answer: z.number().int().min(0),
  explanation: z.string().trim().min(5),
  image: z
    .object({
      shape: z.enum(['warning', 'prohibitory', 'mandatory', 'info', 'stop', 'yield', 'end']),
      symbol: z.string().optional(),
      text: z.string().max(4).optional(),
      slash: z.boolean().optional(),
    })
    .nullable()
    .optional(),
  active: z.boolean().optional(),
});

export async function adminRoutes(app: FastifyInstance) {
  const { db, config } = app;
  const adminEmails = new Set((config.ADMIN_EMAILS ?? '').split(',').map((e) => e.trim().toLowerCase()).filter(Boolean));

  const requireAdmin = async (req: FastifyRequest, reply: FastifyReply) => {
    await app.authenticate(req, reply);
    if (reply.sent) return;
    const u = await db.query.users.findFirst({ where: eq(users.id, req.userId), columns: { role: true, email: true } });
    if (!u || (u.role !== 'admin' && !(u.email && adminEmails.has(u.email)))) {
      return reply.code(403).send({ error: 'forbidden', message: 'Yönetici yetkisi gerekiyor' });
    }
  };
  app.addHook('preHandler', requireAdmin);

  app.get('/me', async (req) => {
    const u = await db.query.users.findFirst({ where: eq(users.id, req.userId), columns: { id: true, email: true, name: true } });
    return u;
  });

  // MARK: Genel bakış

  app.get('/overview', async (req) => {
    const { days } = z.object({ days: z.coerce.number().int().min(1).max(180).default(30) }).parse(req.query);
    const now = Date.now();
    const since = new Date(now - days * DAY);

    const [[{ total }], [{ fresh }], recentEvents, allPurchases, examRows, eventCounts] = await Promise.all([
      db.select({ total: count() }).from(users),
      db.select({ fresh: count() }).from(users).where(gte(users.createdAt, since)),
      db.select({ userId: events.userId, deviceId: events.deviceId, sessionId: events.sessionId, at: events.at }).from(events).where(gte(events.at, since)),
      db.select().from(purchases),
      db.select({ kind: exams.kind, startedAt: exams.startedAt, finishedAt: exams.finishedAt }).from(exams).where(gte(exams.startedAt, since)),
      db.select({ name: events.name, n: count() }).from(events).where(gte(events.at, since)).groupBy(events.name).orderBy(desc(count())).limit(15),
    ]);

    // Aktif haklar
    const active = allPurchases.filter((p) => p.userId && !p.revokedAt && (!p.expiresAt || p.expiresAt.getTime() > now));
    const premiumUsers = new Set(active.filter((p) => PRODUCTS[p.productId]?.scopes.includes('exams')).map((p) => p.userId));
    const byProduct: Record<string, number> = {};
    for (const p of active) byProduct[p.productId] = (byProduct[p.productId] ?? 0) + 1;
    const buyers = new Set(allPurchases.filter((p) => p.userId).map((p) => p.userId));

    // Aktif kullanıcılar ve süre
    const actor = (e: { userId: string | null; deviceId: string }) => e.userId ?? `d:${e.deviceId}`;
    const activeIn = (ms: number) => new Set(recentEvents.filter((e) => e.at.getTime() >= now - ms).map(actor)).size;
    const sessions = sessionsFrom(recentEvents);
    const totalSec = sessions.reduce((a, s) => a + s.durationSec, 0);
    const actors = new Set(sessions.map((s) => s.userId ?? `d:${s.deviceId}`));

    // Günlük seriler
    const series = new Map<string, { date: string; newUsers: number; activeUsers: Set<string>; purchases: number; exams: number; minutes: number }>();
    for (let t = now - (days - 1) * DAY; t <= now; t += DAY) {
      const d = dayKey(new Date(t));
      series.set(d, { date: d, newUsers: 0, activeUsers: new Set(), purchases: 0, exams: 0, minutes: 0 });
    }
    const newUserRows = await db.select({ createdAt: users.createdAt }).from(users).where(gte(users.createdAt, since));
    for (const u of newUserRows) { const s = series.get(dayKey(u.createdAt)); if (s) s.newUsers++; }
    for (const e of recentEvents) series.get(dayKey(e.at))?.activeUsers.add(actor(e));
    for (const p of allPurchases) { const s = series.get(dayKey(p.purchasedAt)); if (s) s.purchases++; }
    for (const x of examRows) { const s = series.get(dayKey(x.startedAt)); if (s) s.exams++; }
    for (const s of sessions) { const d = series.get(dayKey(new Date(s.start))); if (d) d.minutes += s.durationSec / 60; }

    const finished = examRows.filter((x) => x.finishedAt);
    return {
      range: { days, since: since.toISOString() },
      users: { total, new: fresh, dau: activeIn(DAY), wau: activeIn(7 * DAY), mau: activeIn(30 * DAY) },
      revenue: {
        premiumUsers: premiumUsers.size,
        buyersAllTime: buyers.size,
        conversion: total ? Math.round((buyers.size / total) * 1000) / 10 : 0,
        activeByProduct: byProduct,
      },
      engagement: {
        sessions: sessions.length,
        avgSessionMin: sessions.length ? Math.round((totalSec / sessions.length / 60) * 10) / 10 : 0,
        avgMinutesPerUser: actors.size ? Math.round((totalSec / actors.size / 60) * 10) / 10 : 0,
        examsStarted: examRows.length,
        examsFinished: finished.length,
        dailyCompleted: finished.filter((x) => x.kind === 'daily').length,
      },
      topEvents: eventCounts,
      series: [...series.values()].map((s) => ({ ...s, activeUsers: s.activeUsers.size, minutes: Math.round(s.minutes) })),
    };
  });

  // MARK: Kullanıcılar

  app.get('/users', async (req) => {
    const q = z.object({ q: z.string().optional(), page: z.coerce.number().int().min(1).default(1), filter: z.enum(['all', 'premium']).default('all') }).parse(req.query);
    const PAGE = 50;
    const where = q.q ? or(like(users.email, `%${q.q.toLowerCase()}%`), like(users.name, `%${q.q}%`)) : undefined;
    let rows = await db.select().from(users).where(where).orderBy(desc(users.createdAt));

    const ids = rows.map((r) => r.id);
    const [userPurchases, examCounts, userEvents] = ids.length
      ? await Promise.all([
          db.select().from(purchases).where(inArray(purchases.userId, ids)),
          db.select({ userId: exams.userId, n: count() }).from(exams).where(inArray(exams.userId, ids)).groupBy(exams.userId),
          db.select({ userId: events.userId, deviceId: events.deviceId, sessionId: events.sessionId, at: events.at }).from(events).where(inArray(events.userId, ids)),
        ])
      : [[], [], []];
    const now = Date.now();
    const premiumOf = new Map<string, string>();
    for (const p of userPurchases) {
      if (p.userId && !p.revokedAt && (!p.expiresAt || p.expiresAt.getTime() > now)) premiumOf.set(p.userId, p.productId);
    }
    const timeOf = new Map<string, number>();
    for (const s of sessionsFrom(userEvents)) if (s.userId) timeOf.set(s.userId, (timeOf.get(s.userId) ?? 0) + s.durationSec);
    const examsOf = new Map(examCounts.map((e) => [e.userId, e.n]));

    if (q.filter === 'premium') rows = rows.filter((r) => premiumOf.has(r.id));
    const total = rows.length;
    rows = rows.slice((q.page - 1) * PAGE, q.page * PAGE);

    return {
      total,
      page: q.page,
      pageSize: PAGE,
      users: rows.map((u) => ({
        id: u.id,
        email: u.email,
        name: u.name,
        role: u.role,
        signIn: u.appleSub ? 'apple' : 'email',
        createdAt: u.createdAt.toISOString(),
        lastSeenAt: u.lastSeenAt?.toISOString() ?? null,
        product: premiumOf.get(u.id) ?? null,
        exams: examsOf.get(u.id) ?? 0,
        minutes: Math.round((timeOf.get(u.id) ?? 0) / 60),
      })),
    };
  });

  app.get('/users/:id', async (req, reply) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const u = await db.query.users.findFirst({ where: eq(users.id, id) });
    if (!u) return reply.code(404).send({ error: 'not_found' });
    const [ent, userPurchases, userExams, recent, all] = await Promise.all([
      getEntitlements(db, id),
      db.select().from(purchases).where(eq(purchases.userId, id)).orderBy(desc(purchases.purchasedAt)),
      db.select().from(exams).where(eq(exams.userId, id)).orderBy(desc(exams.startedAt)).limit(30),
      db.select().from(events).where(eq(events.userId, id)).orderBy(desc(events.at)).limit(150),
      db.select({ userId: events.userId, deviceId: events.deviceId, sessionId: events.sessionId, at: events.at }).from(events).where(eq(events.userId, id)),
    ]);
    const sessions = sessionsFrom(all);
    return {
      user: { id: u.id, email: u.email, name: u.name, role: u.role, createdAt: u.createdAt, lastSeenAt: u.lastSeenAt, signIn: u.appleSub ? 'apple' : 'email' },
      entitlements: ent,
      purchases: userPurchases,
      exams: userExams.map((e) => ({
        id: e.id, kind: e.kind, startedAt: e.startedAt, finishedAt: e.finishedAt,
        score: e.finishedAt && e.questionIds.length ? Math.round(((e.correct ?? 0) / e.questionIds.length) * 100) : null,
      })),
      time: { sessions: sessions.length, minutes: Math.round(sessions.reduce((a, s) => a + s.durationSec, 0) / 60) },
      events: recent.map((e) => ({ name: e.name, props: e.props, at: e.at })),
    };
  });

  app.patch('/users/:id', async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const { role } = z.object({ role: z.enum(['user', 'admin']) }).parse(req.body);
    await db.update(users).set({ role }).where(eq(users.id, id));
    return { ok: true };
  });

  // MARK: İçerik

  app.get('/questions', async (req) => {
    const q = z.object({ topic: z.string().optional(), q: z.string().optional() }).parse(req.query);
    const [rows, ts, reportCounts] = await Promise.all([
      db.select().from(questions)
        .where(and(q.topic ? eq(questions.topicId, q.topic) : undefined, q.q ? like(questions.text, `%${q.q}%`) : undefined))
        .orderBy(asc(questions.topicId), asc(questions.id)),
      db.select().from(topics).orderBy(asc(topics.sort)),
      db.select({ questionId: questionReports.questionId, n: count() }).from(questionReports).where(eq(questionReports.resolved, false)).groupBy(questionReports.questionId),
    ]);
    const reports = new Map(reportCounts.map((r) => [r.questionId, r.n]));
    return { topics: ts, questions: rows.map((r) => ({ ...r, openReports: reports.get(r.id) ?? 0 })) };
  });

  app.post('/questions', async (req, reply) => {
    const body = questionBody.parse(req.body);
    if (body.answer >= body.options.length) return reply.code(400).send({ error: 'validation', message: 'Doğru cevap şıklardan biri olmalı' });
    const id = `adm${Date.now().toString(36)}`;
    const [row] = await db.insert(questions).values({ ...body, id, image: body.image ?? null }).returning();
    return reply.code(201).send(row);
  });

  app.patch('/questions/:id', async (req, reply) => {
    const { id } = z.object({ id: z.string() }).parse(req.params);
    const body = questionBody.partial().parse(req.body);
    const [row] = await db.update(questions).set(body).where(eq(questions.id, id)).returning();
    if (!row) return reply.code(404).send({ error: 'not_found' });
    return row;
  });

  app.get('/reports', async () => {
    const rows = await db
      .select({ id: questionReports.id, questionId: questionReports.questionId, message: questionReports.message, createdAt: questionReports.createdAt, resolved: questionReports.resolved, text: questions.text })
      .from(questionReports)
      .innerJoin(questions, eq(questions.id, questionReports.questionId))
      .orderBy(asc(questionReports.resolved), desc(questionReports.createdAt))
      .limit(200);
    return { reports: rows };
  });

  app.patch('/reports/:id', async (req) => {
    const { id } = z.object({ id: z.uuid() }).parse(req.params);
    const { resolved } = z.object({ resolved: z.boolean() }).parse(req.body);
    await db.update(questionReports).set({ resolved }).where(eq(questionReports.id, id));
    return { ok: true };
  });

  app.get('/fees', async () => {
    const rows = await db.select().from(feeItems).orderBy(desc(feeItems.validFrom), asc(feeItems.sort), asc(feeItems.licenseClass));
    return { fees: rows };
  });

  app.patch('/fees/:id', async (req, reply) => {
    const { id } = z.object({ id: z.string() }).parse(req.params);
    const body = z.object({ amountKurus: z.number().int().min(0), isEstimate: z.boolean().optional(), source: z.string().max(120).optional() }).parse(req.body);
    const [row] = await db.update(feeItems).set(body).where(eq(feeItems.id, id)).returning();
    if (!row) return reply.code(404).send({ error: 'not_found' });
    return row;
  });

}
