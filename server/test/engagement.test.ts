import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/build-app.ts';
import { loadConfig } from '../src/config.ts';
import { fakeVerifier } from './fake-verifier.ts';

const app = await buildApp(
  loadConfig({ JWT_SECRET: 'e'.repeat(40), DATABASE_URL: ':memory:', NODE_ENV: 'test', ADMIN_EMAILS: 'admin@test.com' }),
  { verifier: fakeVerifier, storage: null },
);
after(() => app.close());

const register = async (email: string) => {
  const body = (await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: 'gizli1234' } })).json();
  return { id: body.user.id as string, auth: { authorization: `Bearer ${body.accessToken}` } };
};
const user = await register('kursiyer@test.com');
const admin = await register('admin@test.com');

type Q = { id: string; answer: number | null; options: string[]; image: unknown };

test('gerçek sınav modu: cevaplar gizli, değiştirilebilir, bitince dökümde açılır', async () => {
  const exam = (await app.inject({ method: 'POST', url: '/v1/study/exams', headers: user.auth, payload: { kind: 'real' } })).json();
  assert.equal(exam.questions.length, 50);
  assert.ok(exam.questions.every((q: Q) => q.answer === null), 'doğru cevap gönderilmemeli');

  const first = exam.questions[0] as Q;
  const r = (await app.inject({ method: 'POST', url: `/v1/study/exams/${exam.id}/answers`, headers: user.auth, payload: { questionId: first.id, choice: 0 } })).json();
  assert.deepEqual(r, { recorded: true });
  // aynı soruya tekrar cevap verilebilir
  const again = await app.inject({ method: 'POST', url: `/v1/study/exams/${exam.id}/answers`, headers: user.auth, payload: { questionId: first.id, choice: 1 } });
  assert.equal(again.statusCode, 200);

  assert.equal((await app.inject({ method: 'GET', url: `/v1/study/exams/${exam.id}/review`, headers: user.auth })).statusCode, 409);
  await app.inject({ method: 'POST', url: `/v1/study/exams/${exam.id}/finish`, headers: user.auth, payload: { durationSec: 100 } });
  const review = (await app.inject({ method: 'GET', url: `/v1/study/exams/${exam.id}/review`, headers: user.auth })).json();
  assert.equal(review.items.length, 50);
  assert.equal(review.items[0].choice, 1);
  assert.equal(typeof review.items[0].question.answer, 'number');
  assert.equal(review.summary.wrong + review.summary.correct, 50);
});

test('deneme sınavı e-sınav konu dağılımına göre seçilir ve levha soruları görsel içerir', async () => {
  const exam = (await app.inject({ method: 'POST', url: '/v1/study/exams', headers: user.auth, payload: { kind: 'mock' } })).json();
  const byTopic: Record<string, number> = {};
  for (const q of exam.questions) byTopic[q.topicId] = (byTopic[q.topicId] ?? 0) + 1;
  assert.ok(byTopic.trafik! >= 23);
  assert.ok(byTopic.motor === 9 && byTopic.adab === 6);
  const bank = (await app.inject({ method: 'GET', url: '/v1/admin/questions?topic=trafik', headers: admin.auth })).json();
  assert.equal(bank.questions.filter((q: Q) => q.image !== null).length, 14);
});

test('günlük 10 soru: gün içinde aynı set döner, bitirince seri başlar', async () => {
  const before = (await app.inject({ method: 'GET', url: '/v1/study/daily', headers: user.auth })).json();
  assert.equal(before.started, false);
  assert.equal(before.streak, 0);

  const a = (await app.inject({ method: 'POST', url: '/v1/study/exams', headers: user.auth, payload: { kind: 'daily' } })).json();
  assert.equal(a.questions.length, 10);
  const b = (await app.inject({ method: 'POST', url: '/v1/study/exams', headers: user.auth, payload: { kind: 'daily' } })).json();
  assert.equal(b.id, a.id, 'aynı gün ikinci kez başlatınca aynı sınav dönmeli');

  for (const q of a.questions) {
    await app.inject({ method: 'POST', url: `/v1/study/exams/${a.id}/answers`, headers: user.auth, payload: { questionId: q.id, choice: q.answer } });
  }
  await app.inject({ method: 'POST', url: `/v1/study/exams/${a.id}/finish`, headers: user.auth, payload: { durationSec: 120 } });
  const after = (await app.inject({ method: 'GET', url: '/v1/study/daily', headers: user.auth })).json();
  assert.equal(after.completed, true);
  assert.equal(after.correct, 10);
  assert.equal(after.streak, 1);
  assert.equal(after.best, 1);
});

test('hazırlık skoru deneme ortalaması ve konu kapsamından hesaplanır', async () => {
  const r = (await app.inject({ method: 'GET', url: '/v1/study/readiness', headers: user.auth })).json();
  assert.ok(r.score >= 0 && r.score <= 100);
  assert.equal(r.examsCounted, 1); // gerçek sınav sayılır, yarım deneme sayılmaz
  assert.ok(['low', 'medium', 'high'].includes(r.level));
  assert.ok(r.weakestTopic);
  assert.ok(r.advice.length > 10);
});

test('direksiyon kontrol listesi ve hata bildirimi', async () => {
  const c = (await app.inject({ method: 'GET', url: '/v1/checklist' })).json();
  assert.ok(c.sections.length >= 4);
  const rep = await app.inject({ method: 'POST', url: '/v1/study/questions/trf001/report', headers: user.auth, payload: { message: 'Şıklarda yazım hatası var' } });
  assert.equal(rep.statusCode, 201);
});

test('olaylar toplanır, yönetim paneli metrikleri hesaplar', async () => {
  const t0 = Date.now() - 10 * 60_000;
  const res = await app.inject({
    method: 'POST', url: '/v1/events', headers: user.auth,
    payload: {
      deviceId: 'device-abcdef12', sessionId: 'session-abcdef12', appVersion: '1.0',
      events: [
        { name: 'app_open', at: new Date(t0).toISOString() },
        { name: 'screen_view', props: { screen: 'home' }, at: new Date(t0 + 60_000).toISOString() },
        { name: 'app_background', at: new Date(t0 + 6 * 60_000).toISOString() },
      ],
    },
  });
  assert.equal(res.statusCode, 202);
  assert.equal((await app.inject({ method: 'POST', url: '/v1/events', payload: { deviceId: 'x', sessionId: 'y', events: [] } })).statusCode, 400);

  assert.equal((await app.inject({ method: 'GET', url: '/v1/admin/overview', headers: user.auth })).statusCode, 403);

  const o = (await app.inject({ method: 'GET', url: '/v1/admin/overview?days=7', headers: admin.auth })).json();
  assert.equal(o.users.total, 2);
  assert.equal(o.users.dau, 1);
  assert.equal(o.engagement.avgSessionMin, 6);
  assert.ok(o.engagement.examsStarted >= 3);
  assert.equal(o.series.length, 7);

  const list = (await app.inject({ method: 'GET', url: '/v1/admin/users', headers: admin.auth })).json();
  const me = list.users.find((u: { id: string }) => u.id === user.id);
  assert.equal(me.minutes, 6);
  assert.ok(me.lastSeenAt);

  const detail = (await app.inject({ method: 'GET', url: `/v1/admin/users/${user.id}`, headers: admin.auth })).json();
  assert.equal(detail.events.length, 3);

  const reports = (await app.inject({ method: 'GET', url: '/v1/admin/reports', headers: admin.auth })).json();
  assert.equal(reports.reports.length, 1);

  const page = await app.inject({ method: 'GET', url: '/admin' });
  assert.equal(page.statusCode, 200);
  assert.match(page.body, /Ehliyet Yönetim/);
});

test('admin soru ekler ve pasife alır', async () => {
  const created = await app.inject({
    method: 'POST', url: '/v1/admin/questions', headers: admin.auth,
    payload: { topicId: 'adab', text: 'Deneme sorusu metni?', options: ['A', 'B'], answer: 1, explanation: 'Açıklama metni' },
  });
  assert.equal(created.statusCode, 201);
  const id = created.json().id;
  const off = await app.inject({ method: 'PATCH', url: `/v1/admin/questions/${id}`, headers: admin.auth, payload: { active: false } });
  assert.equal(off.json().active, false);
});
