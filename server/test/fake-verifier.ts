import type { AppStoreVerifier } from '../src/lib/appstore.ts';

/** Testlerde Apple imzası yerine "fake.<base64 JSON>" biçiminde sahte JWS kullanılır. */
const decode = (jws: string) => {
  if (!jws.startsWith('fake.')) throw new Error('bad signature');
  return JSON.parse(Buffer.from(jws.slice(5), 'base64url').toString());
};

export const fakeVerifier: AppStoreVerifier = {
  verifyTransaction: async (jws) => decode(jws),
  verifyNotification: async (payload) => decode(payload),
};

export const fakeJWS = (payload: object) => 'fake.' + Buffer.from(JSON.stringify(payload)).toString('base64url');
