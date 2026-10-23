import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { buildApp } from '../src/build-app.ts';
import { loadConfig } from '../src/config.ts';
import { fakeJWS, fakeVerifier } from './fake-verifier.ts';

const app = await buildApp(loadConfig({ JWT_SECRET: 'y'.repeat(40), DATABASE_URL: ':memory:', NODE_ENV: 'test' }), { verifier: fakeVerifier });
after(() => app.close());

const register = async (email: string) => {
  const res = await app.inject({ method: 'POST', url: '/v1/auth/register', payload: { email, password: 'gizli1234' } });
  const body = res.json();
  return { id: body.user.id as string, auth: { authorization: `Bearer ${body.accessToken}` } };
};

const MONTHLY = 'com.melihcaliskan.ehliyet.premium.monthly';
const SIX = 'com.melihcaliskan.ehliyet.premium.6months';
const VIDEOS = 'com.melihcaliskan.ehliyet.videos';
const tx = (over: object) => ({ transactionId: 't1', originalTransactionId: 'o1', productId: MONTHLY, purchaseDate: Date.now(), environment: 'Sandbox', ...over });

const alice = await register('alice@test.com');
const bob = await register('bob@test.com');

test('işlem doğrulanınca premium açılır', async () => {
  const res = await app.inject({
    method: 'POST', url: '/v1/iap/transactions', headers: alice.auth,
    payload: { signedTransaction: fakeJWS(tx({ appAccountToken: alice.id, expiresDate: Date.now() + 30 * 86_400_000 })) },
  });
  assert.equal(res.statusCode, 200);
  assert.equal(res.json().isPremium, true);
  assert.deepEqual(res.json().scopes.sort(), ['exams', 'no_ads', 'routes', 'videos']);
});

test('geçersiz imza reddedilir', async () => {
  const res = await app.inject({ method: 'POST', url: '/v1/iap/transactions', headers: alice.auth, payload: { signedTransaction: 'eyJhbGciOiJFUzI1NiJ9.x.y' } });
  assert.equal(res.statusCode, 400);
  assert.equal(res.json().error, 'invalid_signature');
});

test('başkasının satın alması kullanılamaz', async () => {
  const byToken = await app.inject({
    method: 'POST', url: '/v1/iap/transactions', headers: bob.auth,
    payload: { signedTransaction: fakeJWS(tx({ transactionId: 't9', appAccountToken: alice.id })) },
  });
  assert.equal(byToken.statusCode, 403);

  // appAccountToken olmasa bile, başka hesaba bağlı işlem aktarılamaz
  const replay = await app.inject({
    method: 'POST', url: '/v1/iap/transactions', headers: bob.auth,
    payload: { signedTransaction: fakeJWS(tx({ expiresDate: Date.now() + 86_400_000 })) },
  });
  assert.equal(replay.statusCode, 403);
});

test('sadece videolar paketi kısmi yetki verir; 6 aylık paket süreyi kendisi hesaplar', async () => {
  const v = await app.inject({
    method: 'POST', url: '/v1/iap/transactions', headers: bob.auth,
    payload: { signedTransaction: fakeJWS(tx({ transactionId: 'v1', originalTransactionId: 'v1', productId: VIDEOS })) },
  });
  assert.deepEqual(v.json().scopes, ['videos']);
  assert.equal(v.json().isPremium, false);

  const sixAgo = new Date(); sixAgo.setMonth(sixAgo.getMonth() - 7);
  const old = await app.inject({
    method: 'POST', url: '/v1/iap/transactions', headers: bob.auth,
    payload: { signedTransaction: fakeJWS(tx({ transactionId: 's1', originalTransactionId: 's1', productId: SIX, purchaseDate: sixAgo.getTime() })) },
  });
  assert.equal(old.json().isPremium, false, '7 ay önce alınan 6 aylık paket süresi dolmuş olmalı');
});

test('sunucu bildirimi: iade premium hakkını kaldırır', async () => {
  const refund = fakeJWS({
    notificationType: 'REFUND',
    data: { signedTransactionInfo: fakeJWS(tx({ revocationDate: Date.now(), expiresDate: Date.now() + 30 * 86_400_000 })) },
  });
  const res = await app.inject({ method: 'POST', url: '/v1/iap/notifications', payload: { signedPayload: refund } });
  assert.equal(res.statusCode, 200);

  const ent = await app.inject({ method: 'GET', url: '/v1/iap/entitlements', headers: alice.auth });
  assert.equal(ent.json().isPremium, false);
});

test('sunucu bildirimi: yenileme süreyi uzatır', async () => {
  const renew = fakeJWS({
    notificationType: 'DID_RENEW',
    data: { signedTransactionInfo: fakeJWS(tx({ transactionId: 't2', expiresDate: Date.now() + 60 * 86_400_000 })) },
  });
  await app.inject({ method: 'POST', url: '/v1/iap/notifications', payload: { signedPayload: renew } });
  const ent = await app.inject({ method: 'GET', url: '/v1/iap/entitlements', headers: alice.auth });
  assert.equal(ent.json().isPremium, true);
});

test('geri yükleme hatalı işlemleri atlar', async () => {
  const res = await app.inject({
    method: 'POST', url: '/v1/iap/restore', headers: alice.auth,
    payload: { signedTransactions: ['bozuk-imza', fakeJWS(tx({ transactionId: 't3', expiresDate: Date.now() + 86_400_000 }))] },
  });
  assert.equal(res.statusCode, 200);
  assert.equal(res.json().isPremium, true);
});
