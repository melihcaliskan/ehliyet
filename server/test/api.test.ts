import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/build-app.ts';
import { loadConfig } from '../src/config.ts';

import { fakeVerifier } from './fake-verifier.ts';

const app = await buildApp(loadConfig({ JWT_SECRET: 'x'.repeat(40), DATABASE_URL: ':memory:', NODE_ENV: 'test' }), { verifier: fakeVerifier });
before(() => app.ready());
after(() => app.close());

let access = '';
let refresh = '';

test('kayıt, giriş ve /me', async () => {
  const reg = await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email: 'Ali@Test.com', password: 'gizli1234', name: 'Ali' } });
  assert.equal(reg.statusCode, 201);
  assert.equal(reg.json().user.email, 'ali@test.com');

  const dup = await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email: 'ali@test.com', password: 'gizli1234' } });
  assert.equal(dup.statusCode, 409);

  const bad = await app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: 'ali@test.com', password: 'yanlis123' } });
  assert.equal(bad.statusCode, 401);

  const login = await app.inject({ method: 'POST', url: '/v1/auth/login', payload: { email: 'ali@test.com', password: 'gizli1234' } });
  assert.equal(login.statusCode, 200);
  ({ accessToken: access, refreshToken: refresh } = login.json());

  const me = await app.inject({ method: 'GET', url: '/v1/auth/me', headers: { authorization: `Bearer ${access}` } });
  assert.equal(me.statusCode, 200);
  assert.equal(me.json().entitlements.isPremium, false);

  assert.equal((await app.inject({ method: 'GET', url: '/v1/auth/me' })).statusCode, 401);
});

test('refresh rotasyonu ve yeniden kullanım tespiti', async () => {
  const r1 = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken: refresh } });
  assert.equal(r1.statusCode, 200);
  const next = r1.json().refreshToken;

  // Eski token tekrar kullanılırsa reddedilir ve tüm aile iptal olur
  const reuse = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken: refresh } });
  assert.equal(reuse.statusCode, 401);
  const after = await app.inject({ method: 'POST', url: '/v1/auth/refresh', payload: { refreshToken: next } });
  assert.equal(after.statusCode, 401);
});

test('harç ve ücretler', async () => {
  const res = await app.inject({ method: 'GET', url: '/v1/fees?class=B' });
  assert.equal(res.statusCode, 200);
  assert.equal(res.json().totalKurus, 4227944); // Haziran 2026 tarifesi: 42.279,44 ₺
  assert.equal(res.json().isEstimate, false);

  const a = (await app.inject({ method: 'GET', url: '/v1/fees?class=A2' })).json();
  assert.equal(a.sections[0].items[0].amountKurus, Math.round(223990 * 1.4));
  assert.equal(a.isEstimate, true);

  const noCourse = await app.inject({ method: 'GET', url: '/v1/fees?class=B&includeCourse=false' });
  assert.equal(noCourse.json().totalKurus, 4227944 - 2500000);

  assert.equal((await app.inject({ method: 'GET', url: '/v1/fees?class=X' })).statusCode, 400);
});

test('sınav takvimi: oturumlar ve randevular', async () => {
  const s = await app.inject({ method: 'GET', url: '/v1/calendar/sessions?month=2026-11' });
  assert.equal(s.json().sessions.length, 0);
  assert.match(s.json().info.eSinav, /her günü/);

  assert.equal((await app.inject({ method: 'GET', url: '/v1/calendar/appointments' })).statusCode, 401);

  const auth = { authorization: `Bearer ${access}` };
  const created = await app.inject({
    method: 'POST', url: '/v1/calendar/appointments', headers: auth,
    payload: { kind: 'e_sinav', title: 'E-Sınav (Teorik)', startsAt: '2026-11-12T10:00:00+03:00', location: 'Kadıköy MTSK' },
  });
  assert.equal(created.statusCode, 201);
  const id = created.json().id;

  const patched = await app.inject({ method: 'PATCH', url: `/v1/calendar/appointments/${id}`, headers: auth, payload: { location: null } });
  assert.equal(patched.json().location, null);

  const list = await app.inject({ method: 'GET', url: '/v1/calendar/appointments?month=2026-11', headers: auth });
  assert.equal(list.json().appointments.length, 1);

  assert.equal((await app.inject({ method: 'DELETE', url: `/v1/calendar/appointments/${id}`, headers: auth })).statusCode, 204);
});

test('hesap silme', async () => {
  const res = await app.inject({ method: 'DELETE', url: '/v1/auth/me', headers: { authorization: `Bearer ${access}` } });
  assert.equal(res.statusCode, 204);
});

test('sınav kuralları', async () => {
  const res = await app.inject({ method: 'GET', url: '/v1/rules' });
  assert.equal(res.statusCode, 200);
  const body = res.json();
  assert.equal(body.rights.length, 2);
  assert.equal(body.sections[1].steps.length, 6);
});
