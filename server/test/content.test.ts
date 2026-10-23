import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/build-app.ts';
import { loadConfig } from '../src/config.ts';
import { fakeJWS, fakeVerifier } from './fake-verifier.ts';

const app = await buildApp(loadConfig({ JWT_SECRET: 'z'.repeat(40), DATABASE_URL: ':memory:', NODE_ENV: 'test' }), { verifier: fakeVerifier, storage: null });
after(() => app.close());

const register = async (email: string) => {
  const body = (await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: 'gizli1234' } })).json();
  return { id: body.user.id as string, auth: { authorization: `Bearer ${body.accessToken}` } };
};
const grant = (userId: string, auth: Record<string, string>, productId: string, transactionId: string) =>
  app.inject({
    method: 'POST', url: '/v1/iap/transactions', headers: auth,
    payload: { signedTransaction: fakeJWS({ transactionId, originalTransactionId: transactionId, productId, purchaseDate: Date.now(), expiresDate: Date.now() + 86_400_000, appAccountToken: userId, environment: 'Xcode' }) },
  });

const user = await register('ogrenci@test.com');

test('konular soru sayılarıyla gelir', async () => {
  const res = (await app.inject({ method: 'GET', url: '/v1/study/topics' })).json();
  assert.equal(res.topics.length, 4);
  assert.ok(res.topics.every((t: { questionCount: number }) => t.questionCount > 0));
});

test('deneme sınavı: cevaplar kaydedilir, sonuç ve yanlışlar hesaplanır', async () => {
  const start = await app.inject({ method: 'POST', url: '/v1/study/exams', headers: user.auth, payload: { kind: 'mock' } });
  assert.equal(start.statusCode, 201);
  const exam = start.json();
  assert.equal(exam.timeLimitSec, 45 * 60);

  // İlk soruyu yanlış, diğerlerini doğru cevapla
  for (const [i, q] of exam.questions.entries()) {
    const choice = i === 0 ? (q.answer + 1) % q.options.length : q.answer;
    const r = await app.inject({ method: 'POST', url: `/v1/study/exams/${exam.id}/answers`, headers: user.auth, payload: { questionId: q.id, choice } });
    assert.equal(r.json().correct, i !== 0);
  }
  const dup = await app.inject({ method: 'POST', url: `/v1/study/exams/${exam.id}/answers`, headers: user.auth, payload: { questionId: exam.questions[0].id, choice: 0 } });
  assert.equal(dup.statusCode, 409);

  const result = (await app.inject({ method: 'POST', url: `/v1/study/exams/${exam.id}/finish`, headers: user.auth, payload: { durationSec: 600 } })).json();
  assert.equal(result.correct, exam.questions.length - 1);
  assert.equal(result.wrong, 1);
  assert.equal(result.passed, true);

  const wrongs = (await app.inject({ method: 'GET', url: '/v1/study/wrong-answers', headers: user.auth })).json();
  assert.deepEqual(wrongs.questions.map((q: { id: string }) => q.id), [exam.questions[0].id]);

  const progress = (await app.inject({ method: 'GET', url: '/v1/study/progress', headers: user.auth })).json();
  assert.equal(progress.wrongCount, 1);
  assert.equal(progress.mockExams.remaining, 2);

  const history = (await app.inject({ method: 'GET', url: '/v1/study/exams', headers: user.auth })).json();
  assert.equal(history.exams.length, 1);
});

test('ücretsiz kullanıcı 3 denemeden sonra durdurulur, premium devam eder', async () => {
  for (let i = 0; i < 2; i++) {
    assert.equal((await app.inject({ method: 'POST', url: '/v1/study/exams', headers: user.auth, payload: { kind: 'mock' } })).statusCode, 201);
  }
  const blocked = await app.inject({ method: 'POST', url: '/v1/study/exams', headers: user.auth, payload: { kind: 'mock' } });
  assert.equal(blocked.statusCode, 402);
  assert.equal(blocked.json().error, 'free_limit_reached');

  // konu testleri ücretsiz kalır
  assert.equal((await app.inject({ method: 'POST', url: '/v1/study/exams', headers: user.auth, payload: { kind: 'topic', topicId: 'trafik' } })).statusCode, 201);
  // yanlışlar testi premium
  assert.equal((await app.inject({ method: 'POST', url: '/v1/study/exams', headers: user.auth, payload: { kind: 'wrongs' } })).statusCode, 402);

  await grant(user.id, user.auth, 'com.melihcaliskan.ehliyet.premium.monthly', 'p1');
  assert.equal((await app.inject({ method: 'POST', url: '/v1/study/exams', headers: user.auth, payload: { kind: 'mock' } })).statusCode, 201);
  const wrongs = await app.inject({ method: 'POST', url: '/v1/study/exams', headers: user.auth, payload: { kind: 'wrongs' } });
  assert.equal(wrongs.statusCode, 201);
  assert.equal(wrongs.json().questions.length, 1);
});

test('dersler: kilitli videonun adresi gizlenir, video paketiyle açılır', async () => {
  const guest = (await app.inject({ method: 'GET', url: '/v1/lessons?kind=driving' })).json();
  const paralel = guest.lessons.find((l: { id: string }) => l.id === 'd3');
  assert.equal(paralel.locked, true);
  assert.equal(paralel.videoUrl, null);

  const other = await register('video@test.com');
  assert.equal((await app.inject({ method: 'PUT', url: '/v1/lessons/d3/progress', headers: other.auth, payload: { positionSec: 10 } })).statusCode, 402);
  await grant(other.id, other.auth, 'com.melihcaliskan.ehliyet.videos', 'v1');

  const mine = (await app.inject({ method: 'GET', url: '/v1/lessons?kind=driving', headers: other.auth })).json();
  assert.equal(mine.lessons.find((l: { id: string }) => l.id === 'd3').locked, false);

  await app.inject({ method: 'PUT', url: '/v1/lessons/d3/progress', headers: other.auth, payload: { positionSec: 120 } });
  const after = (await app.inject({ method: 'GET', url: '/v1/lessons', headers: other.auth })).json();
  assert.equal(after.resumeLessonId, 'd3');

  const done = (await app.inject({ method: 'PUT', url: '/v1/lessons/d3/progress', headers: other.auth, payload: { positionSec: 9 * 60 } })).json();
  assert.equal(done.completed, true);
});

test('güzergahlar: premium güzergah kilitli, rota scope ile açılır', async () => {
  const cities = (await app.inject({ method: 'GET', url: '/v1/routes/cities' })).json();
  assert.deepEqual(cities.cities.map((c: { name: string }) => c.name), ['Ankara', 'İstanbul']);

  const guest = (await app.inject({ method: 'GET', url: '/v1/routes?city=İstanbul' })).json();
  const uskudar = guest.routes.find((r: { id: string }) => r.id === 'ist-uskudar');
  assert.equal(uskudar.locked, true);
  assert.equal(uskudar.checkpoints.length, 0);
  assert.equal(uskudar.checkpointCount, 3);

  const premium = (await app.inject({ method: 'GET', url: '/v1/routes?city=İstanbul', headers: user.auth })).json();
  assert.equal(premium.routes.find((r: { id: string }) => r.id === 'ist-uskudar').checkpoints.length, 3);
});

test('bildirimler yaklaşan randevuyu içerir', async () => {
  const soon = new Date(Date.now() + 5 * 86_400_000).toISOString();
  await app.inject({ method: 'POST', url: '/v1/calendar/appointments', headers: user.auth, payload: { kind: 'e_sinav', title: 'E-Sınav', startsAt: soon } });
  const res = (await app.inject({ method: 'GET', url: '/v1/notifications', headers: user.auth })).json();
  assert.ok(res.notifications.some((n: { kind: string }) => n.kind === 'appointment'));
});

test('arama Türkçe harf farklarını yok sayar', async () => {
  const res = (await app.inject({ method: 'GET', url: '/v1/search?q=' + encodeURIComponent('İLK YARDIM') })).json();
  assert.ok(res.questions.length >= 3);
  const lessons = (await app.inject({ method: 'GET', url: '/v1/search?q=park' })).json();
  assert.deepEqual(lessons.lessons.map((l: { id: string }) => l.id), ['d3', 'd4']);
  assert.equal((await app.inject({ method: 'GET', url: '/v1/search?q=a' })).statusCode, 400);
});

test('video adresi depolamadan süreli imzalı URL olarak gelir, kilitliyse hiç gelmez', async () => {
  const signed: string[] = [];
  const app2 = await buildApp(loadConfig({ JWT_SECRET: 'w'.repeat(40), DATABASE_URL: ':memory:', NODE_ENV: 'test' }), {
    verifier: fakeVerifier,
    storage: { signedUrl: async (key) => { signed.push(key); return `https://r2.test/${key}?X-Amz-Signature=abc`; } },
  });
  const res = (await app2.inject({ method: 'GET', url: '/v1/lessons?kind=driving' })).json();
  assert.equal(res.lessons.find((l: { id: string }) => l.id === 'd1').videoUrl, 'https://r2.test/lessons/d1.mp4?X-Amz-Signature=abc');
  assert.equal(res.lessons.find((l: { id: string }) => l.id === 'd3').videoUrl, null);
  assert.ok(!signed.includes('lessons/d3.mp4'), 'kilitli ders için imza üretilmemeli');
  await app2.close();
});
