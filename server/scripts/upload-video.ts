// Kullanım: npm run video:upload -- <dersId> <dosya.mp4>
// Videoyu depolamaya yükler ve dersin video anahtarını günceller.
import { eq } from 'drizzle-orm';
import { loadConfig } from '../src/config.ts';
import { openDatabase } from '../src/db/index.ts';
import { lessons } from '../src/db/schema.ts';
import { uploadFile } from '../src/lib/storage.ts';

const [lessonId, file] = process.argv.slice(2);
if (!lessonId || !file) {
  console.error('Kullanım: npm run video:upload -- <dersId> <dosya.mp4>');
  process.exit(1);
}

const config = loadConfig();
if (!config.STORAGE_BUCKET) throw new Error('.env içinde STORAGE_* değişkenleri tanımlı değil');

const { db, close } = await openDatabase(config.DATABASE_URL, config.DATABASE_AUTH_TOKEN);
const lesson = await db.query.lessons.findFirst({ where: eq(lessons.id, lessonId) });
if (!lesson) throw new Error(`Ders bulunamadı: ${lessonId}`);

const key = `lessons/${lessonId}.mp4`;
const bytes = await uploadFile(config, key, file);
await db.update(lessons).set({ videoKey: key }).where(eq(lessons.id, lessonId));
console.log(`✓ ${lesson.title} → ${key} (${(bytes / 1_048_576).toFixed(1)} MB)`);
close();
