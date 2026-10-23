import type { FastifyInstance } from 'fastify';
import { and, asc, eq, isNull, like, or, type SQL } from 'drizzle-orm';
import { z } from 'zod';
import { appointments, examSessions } from '../db/schema.ts';

const kind = z.enum(['e_sinav', 'direksiyon']);
const month = z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/, 'Ay YYYY-MM biçiminde olmalı');

const sessionsQuery = z.object({ month: month.optional(), city: z.string().optional(), kind: kind.optional() });
const appointmentBody = z.object({
  kind,
  title: z.string().trim().min(1).max(80),
  startsAt: z.iso.datetime({ offset: true }),
  location: z.string().trim().max(120).nullish(),
});

const toAppointment = ({ userId: _u, createdAt: _c, ...a }: typeof appointments.$inferSelect) => a;

export async function calendarRoutes(app: FastifyInstance) {
  const { db } = app;

  // Herkese açık resmi sınav oturumları
  app.get('/sessions', async (req) => {
    const q = sessionsQuery.parse(req.query);
    const where: SQL[] = [];
    if (q.month) where.push(like(examSessions.date, `${q.month}-%`));
    if (q.kind) where.push(eq(examSessions.kind, q.kind));
    if (q.city) where.push(or(isNull(examSessions.city), eq(examSessions.city, q.city))!);
    const sessions = await db.select().from(examSessions).where(and(...where)).orderBy(asc(examSessions.date));
    return {
      sessions,
      info: {
        eSinav: 'E-sınav 81 ilde e-sınav salonlarında, randevuyla haftanın her günü yapılır. Randevunu sürücü kursun MEBBİS üzerinden alır.',
        direksiyon: 'Direksiyon sınavı tarihini sürücü kursun belirler; sınav yaklaşık 40 dakika sürer.',
        source: 'MEB ODSGM 2026 Sınav Uygulama Takvimi',
      },
    };
  });

  // Kullanıcının randevuları (oturum gerekli)
  app.register(async (priv) => {
    priv.addHook('preHandler', app.authenticate);
    const own = (userId: string, id: string) => and(eq(appointments.id, id), eq(appointments.userId, userId));

    priv.get('/appointments', async (req) => {
      const { month: m } = z.object({ month: month.optional() }).parse(req.query);
      const rows = await db
        .select()
        .from(appointments)
        .where(and(eq(appointments.userId, req.userId), m ? like(appointments.startsAt, `${m}-%`) : undefined))
        .orderBy(asc(appointments.startsAt));
      return { appointments: rows.map(toAppointment) };
    });

    priv.post('/appointments', async (req, reply) => {
      const body = appointmentBody.parse(req.body);
      const [row] = await db.insert(appointments).values({ ...body, userId: req.userId }).returning();
      return reply.code(201).send(toAppointment(row!));
    });

    priv.patch('/appointments/:id', async (req, reply) => {
      const { id } = z.object({ id: z.uuid() }).parse(req.params);
      const body = appointmentBody.partial().parse(req.body);
      const [row] = await db.update(appointments).set(body).where(own(req.userId, id)).returning();
      if (!row) return reply.code(404).send({ error: 'not_found' });
      return toAppointment(row);
    });

    priv.delete('/appointments/:id', async (req, reply) => {
      const { id } = z.object({ id: z.uuid() }).parse(req.params);
      const res = await db.delete(appointments).where(own(req.userId, id)).returning({ id: appointments.id });
      return reply.code(res.length ? 204 : 404).send();
    });
  });
}
