import type { FastifyInstance } from 'fastify';
import { and, asc, eq, isNull, lte, max, or } from 'drizzle-orm';
import { z } from 'zod';
import { feeItems } from '../db/schema.ts';

const LICENSE_CLASSES = ['A1', 'A2', 'A', 'B', 'BE', 'C', 'D', 'F'] as const;

const feesQuery = z.object({
  class: z.enum(LICENSE_CLASSES).default('B'),
  includeCourse: z.stringbool().default(true),
});

type FeeRow = typeof feeItems.$inferSelect;

export async function feeRoutes(app: FastifyInstance) {
  const { db } = app;

  app.get('/classes', async () => ({ classes: LICENSE_CLASSES }));

  app.get('/', async (req, reply) => {
    const q = feesQuery.parse(req.query);
    const today = new Date().toISOString().slice(0, 10);

    // En güncel tarife dönemi
    const [{ latest } = { latest: null }] = await db
      .select({ latest: max(feeItems.validFrom) })
      .from(feeItems)
      .where(lte(feeItems.validFrom, today));
    if (!latest) return reply.code(404).send({ error: 'no_tariff' });

    let rows = await db
      .select()
      .from(feeItems)
      .where(and(eq(feeItems.validFrom, latest), or(isNull(feeItems.licenseClass), eq(feeItems.licenseClass, q.class))))
      .orderBy(asc(feeItems.sort));
    if (!q.includeCourse) rows = rows.filter((r) => !r.isCourseFee);

    const item = (r: FeeRow) => ({ id: r.id, title: r.title, amountKurus: r.amountKurus, isCourseFee: r.isCourseFee, isEstimate: r.isEstimate });
    const sum = (rs: FeeRow[]) => rs.reduce((t, r) => t + r.amountKurus, 0);
    const state = rows.filter((r) => r.category === 'state');
    const course = rows.filter((r) => r.category === 'course');

    reply.header('Cache-Control', 'public, max-age=3600');
    return {
      licenseClass: q.class,
      currency: 'TRY',
      validFrom: latest,
      totalKurus: sum(rows),
      isEstimate: rows.some((r) => r.isEstimate),
      sources: [...new Set(rows.map((r) => r.source).filter(Boolean))],
      sections: [
        { id: 'state', title: 'Devlet harçları', items: state.map(item), subtotalKurus: sum(state) },
        { id: 'course', title: 'Sınav ve kurs', items: course.map(item), subtotalKurus: sum(course) },
      ],
      note: q.class === 'B'
        ? 'Kurs ücreti il ve ilçeye göre değişir. Harçlar vergi dairesine veya anlaşmalı bankalara ödenir.'
        : 'Bu sınıf için kurs ücreti eklenmedi; kursundan öğren. Harçlar vergi dairesine veya anlaşmalı bankalara ödenir.',
    };
  });
}
