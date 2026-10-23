import { createHash, randomBytes, randomUUID, scrypt, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import { and, eq, isNull } from 'drizzle-orm';
import { SignJWT, jwtVerify, createRemoteJWKSet } from 'jose';
import type { Config } from '../config.ts';
import type { DB } from '../db/index.ts';
import { refreshTokens } from '../db/schema.ts';

const scryptAsync = promisify(scrypt) as (pw: string, salt: Buffer, len: number) => Promise<Buffer>;

// MARK: Şifre

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const key = await scryptAsync(password, salt, 64);
  return `scrypt$${salt.toString('base64')}$${key.toString('base64')}`;
}

export async function verifyPassword(password: string, stored: string): Promise<boolean> {
  const [algo, saltB64, keyB64] = stored.split('$');
  if (algo !== 'scrypt' || !saltB64 || !keyB64) return false;
  const expected = Buffer.from(keyB64, 'base64');
  const actual = await scryptAsync(password, Buffer.from(saltB64, 'base64'), expected.length);
  return timingSafeEqual(actual, expected);
}

// MARK: Token'lar

const sha256 = (s: string) => createHash('sha256').update(s).digest('hex');

export class TokenService {
  private secret: Uint8Array;
  private config: Config;
  private db: DB;

  constructor(config: Config, db: DB) {
    this.config = config;
    this.db = db;
    this.secret = new TextEncoder().encode(config.JWT_SECRET);
  }

  async signAccess(userId: string) {
    return new SignJWT({})
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(userId)
      .setIssuedAt()
      .setIssuer('ehliyet')
      .setExpirationTime(this.config.ACCESS_TOKEN_TTL)
      .sign(this.secret);
  }

  async verifyAccess(token: string): Promise<string> {
    const { payload } = await jwtVerify(token, this.secret, { issuer: 'ehliyet', algorithms: ['HS256'] });
    if (!payload.sub) throw new Error('sub yok');
    return payload.sub;
  }

  /** Opak refresh token üretir; veritabanında yalnızca hash'i tutulur. */
  async issueRefresh(userId: string, familyId: string = randomUUID()): Promise<string> {
    const token = randomBytes(32).toString('base64url');
    await this.db.insert(refreshTokens).values({
      userId,
      tokenHash: sha256(token),
      familyId,
      expiresAt: new Date(Date.now() + this.config.REFRESH_TOKEN_DAYS * 86_400_000),
    });
    return token;
  }

  /**
   * Refresh token'ı döndürür (rotation). Daha önce kullanılmış bir token tekrar gelirse
   * çalınmış kabul edilir ve aynı ailedeki tüm token'lar iptal edilir.
   */
  async rotate(token: string): Promise<{ userId: string; refreshToken: string } | null> {
    const row = await this.db.query.refreshTokens.findFirst({ where: eq(refreshTokens.tokenHash, sha256(token)) });
    if (!row) return null;

    if (row.revokedAt) {
      await this.revokeWhere(eq(refreshTokens.familyId, row.familyId));
      return null;
    }
    if (row.expiresAt < new Date()) return null;

    await this.db.update(refreshTokens).set({ revokedAt: new Date() }).where(eq(refreshTokens.id, row.id));
    return { userId: row.userId, refreshToken: await this.issueRefresh(row.userId, row.familyId) };
  }

  revoke(token: string) {
    return this.revokeWhere(eq(refreshTokens.tokenHash, sha256(token)));
  }

  revokeAllForUser(userId: string) {
    return this.revokeWhere(eq(refreshTokens.userId, userId));
  }

  private async revokeWhere(cond: ReturnType<typeof eq>) {
    await this.db.update(refreshTokens).set({ revokedAt: new Date() }).where(and(cond, isNull(refreshTokens.revokedAt)));
  }

  async issuePair(userId: string) {
    return { accessToken: await this.signAccess(userId), refreshToken: await this.issueRefresh(userId) };
  }
}

// MARK: Sign in with Apple

const appleJWKS = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'));

export type AppleIdentity = { sub: string; email?: string };

export async function verifyAppleIdentityToken(identityToken: string, bundleId: string): Promise<AppleIdentity> {
  const { payload } = await jwtVerify(identityToken, appleJWKS, {
    issuer: 'https://appleid.apple.com',
    audience: bundleId,
  });
  if (!payload.sub) throw new Error('Apple token sub içermiyor');
  return { sub: payload.sub, email: typeof payload.email === 'string' ? payload.email : undefined };
}
