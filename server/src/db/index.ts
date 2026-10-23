import { createHash } from 'node:crypto';
import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createClient } from '@libsql/client';
import { eq } from 'drizzle-orm';
import { drizzle } from 'drizzle-orm/libsql';
import { migrate } from 'drizzle-orm/libsql/migrator';
import * as schema from './schema.ts';
import { seed, seedContent } from './seed.ts';

export type DB = ReturnType<typeof drizzle<typeof schema>>;

/**
 * Turso'ya bağlanır. Yerelde `file:` veya `:memory:` URL'si ile Turso olmadan da çalışır.
 */
export async function openDatabase(url: string, authToken?: string) {
  if (url.startsWith('file:')) mkdirSync(new URL('.', new URL(url, `file://${process.cwd()}/`)), { recursive: true });
  const client = createClient({ url, authToken });
  const db = drizzle(client, { schema, casing: 'snake_case' });
  await migrateOnce(db);
  await seedIfChanged(db);
  return { db, close: () => client.close() };
}

const MIGRATIONS = fileURLToPath(new URL('../../drizzle', import.meta.url));

/** Serverless'te iki örnek aynı anda açılırsa ikincisi çakışabilir; bir kez yeniden dener */
async function migrateOnce(db: DB) {
  try {
    await migrate(db, { migrationsFolder: MIGRATIONS });
  } catch (err) {
    await new Promise((r) => setTimeout(r, 500));
    await migrate(db, { migrationsFolder: MIGRATIONS }).catch(() => { throw err; });
  }
}

/**
 * Seed yalnızca içerik (sorular, dersler, harçlar…) değiştiğinde çalışır.
 * Böylece her soğuk başlangıçta yüzlerce satır yeniden yazılmaz.
 */
async function seedIfChanged(db: DB) {
  const hash = createHash('sha256').update(JSON.stringify(seedContent)).digest('hex').slice(0, 16);
  const row = await db.query.appMeta.findFirst({ where: eq(schema.appMeta.key, 'seed_hash') });
  if (row?.value === hash) return;
  await seed(db);
  await db.insert(schema.appMeta).values({ key: 'seed_hash', value: hash })
    .onConflictDoUpdate({ target: schema.appMeta.key, set: { value: hash } });
}

export { schema };
