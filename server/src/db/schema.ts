import { sql } from 'drizzle-orm';
import { index, integer, primaryKey, real, sqliteTable, text } from 'drizzle-orm/sqlite-core';

const id = () => text('id').primaryKey().$defaultFn(() => crypto.randomUUID());
const createdAt = () => integer('created_at', { mode: 'timestamp_ms' }).notNull().default(sql`(unixepoch() * 1000)`);

export const users = sqliteTable('users', {
  id: id(), // UUID; StoreKit appAccountToken olarak da kullanılır
  email: text('email').unique(),
  passwordHash: text('password_hash'),
  appleSub: text('apple_sub').unique(),
  name: text('name'),
  role: text('role', { enum: ['user', 'admin'] }).notNull().default('user'),
  lastSeenAt: integer('last_seen_at', { mode: 'timestamp_ms' }),
  createdAt: createdAt(),
});

export const refreshTokens = sqliteTable(
  'refresh_tokens',
  {
    id: id(),
    userId: text('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
    tokenHash: text('token_hash').notNull().unique(),
    familyId: text('family_id').notNull(), // rotasyon zinciri; yeniden kullanımda tüm aile iptal edilir
    expiresAt: integer('expires_at', { mode: 'timestamp_ms' }).notNull(),
    revokedAt: integer('revoked_at', { mode: 'timestamp_ms' }),
    createdAt: createdAt(),
  },
  (t) => [index('idx_refresh_user').on(t.userId)],
);

/** App Store'dan doğrulanmış her işlem bir satır; aktif haklar buradan hesaplanır. */
export const purchases = sqliteTable(
  'purchases',
  {
    id: id(),
    userId: text('user_id').references(() => users.id, { onDelete: 'set null' }),
    productId: text('product_id').notNull(),
    transactionId: text('transaction_id').notNull().unique(),
    originalTransactionId: text('original_transaction_id').notNull(),
    environment: text('environment').notNull(), // Production | Sandbox | Xcode
    purchasedAt: integer('purchased_at', { mode: 'timestamp_ms' }).notNull(),
    expiresAt: integer('expires_at', { mode: 'timestamp_ms' }), // NULL = süresiz
    revokedAt: integer('revoked_at', { mode: 'timestamp_ms' }),
    updatedAt: integer('updated_at', { mode: 'timestamp_ms' }).notNull().$defaultFn(() => new Date()).$onUpdateFn(() => new Date()),
  },
  (t) => [index('idx_purchases_user').on(t.userId), index('idx_purchases_original').on(t.originalTransactionId)],
);

export const examSessions = sqliteTable(
  'exam_sessions',
  {
    id: text('id').primaryKey(),
    kind: text('kind', { enum: ['e_sinav', 'direksiyon'] }).notNull(),
    title: text('title').notNull(),
    date: text('date').notNull(), // YYYY-MM-DD
    city: text('city'), // NULL = tüm Türkiye
    note: text('note'),
  },
  (t) => [index('idx_sessions_date').on(t.date)],
);

export const appointments = sqliteTable(
  'appointments',
  {
    id: id(),
    userId: text('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
    kind: text('kind', { enum: ['e_sinav', 'direksiyon'] }).notNull(),
    title: text('title').notNull(),
    startsAt: text('starts_at').notNull(), // ISO 8601, kullanıcının saat dilimiyle
    location: text('location'),
    createdAt: createdAt(),
  },
  (t) => [index('idx_appointments_user').on(t.userId, t.startsAt)],
);

/** Tutarlar kuruş cinsinden */
export const feeItems = sqliteTable('fee_items', {
  id: text('id').primaryKey(),
  category: text('category', { enum: ['state', 'course'] }).notNull(),
  title: text('title').notNull(),
  amountKurus: integer('amount_kurus').notNull(),
  licenseClass: text('license_class'), // NULL = tüm sınıflar
  isCourseFee: integer('is_course_fee', { mode: 'boolean' }).notNull().default(false),
  sort: integer('sort').notNull().default(0),
  validFrom: text('valid_from').notNull(), // YYYY-MM-DD; en güncel tarife seçilir
  isEstimate: integer('is_estimate', { mode: 'boolean' }).notNull().default(false), // resmi kaynakla doğrulanmadı
  source: text('source'),
});

/**
 * Levha görseli. Görsel dosyası yerine çizim tarifi saklanır; iOS levhayı vektörel çizer.
 * shape: warning = kırmızı kenarlı üçgen, prohibitory = kırmızı kenarlı daire,
 * mandatory = mavi daire, info = mavi kare, stop = sekizgen, yield = ters üçgen
 */
export type SignImage = {
  shape: 'warning' | 'prohibitory' | 'mandatory' | 'info' | 'stop' | 'yield' | 'end';
  symbol?: string; // SF Symbol adı
  text?: string; // ör. "50"
  slash?: boolean; // yasak levhalarındaki kırmızı çapraz çizgi
};

// MARK: - İçerik

export const topics = sqliteTable('topics', {
  id: text('id').primaryKey(),
  name: text('name').notNull(),
  icon: text('icon').notNull(), // SF Symbol adı
  color: text('color').notNull(), // #RRGGBB
  sort: integer('sort').notNull().default(0),
});

export const questions = sqliteTable(
  'questions',
  {
    id: text('id').primaryKey(),
    topicId: text('topic_id').notNull().references(() => topics.id),
    text: text('text').notNull(),
    options: text('options', { mode: 'json' }).$type<string[]>().notNull(),
    answer: integer('answer').notNull(), // options içindeki doğru şıkkın indeksi
    explanation: text('explanation').notNull(),
    source: text('source'), // ör. "2025 Mart e-sınav"
    image: text('image', { mode: 'json' }).$type<SignImage | null>(), // levha sorusu ise çizim tarifi
    active: integer('active', { mode: 'boolean' }).notNull().default(true),
  },
  (t) => [index('idx_questions_topic').on(t.topicId)],
);

/** Kullanıcının çözdüğü her soru; ilerleme ve "Yanlışlarım" buradan hesaplanır */
export const answers = sqliteTable(
  'answers',
  {
    id: id(),
    userId: text('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
    questionId: text('question_id').notNull().references(() => questions.id),
    examId: text('exam_id').references(() => exams.id, { onDelete: 'cascade' }),
    choice: integer('choice').notNull(),
    correct: integer('correct', { mode: 'boolean' }).notNull(),
    answeredAt: integer('answered_at', { mode: 'timestamp_ms' }).notNull().$defaultFn(() => new Date()),
  },
  (t) => [index('idx_answers_user_question').on(t.userId, t.questionId, t.answeredAt)],
);

export const exams = sqliteTable(
  'exams',
  {
    id: id(),
    userId: text('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
    kind: text('kind', { enum: ['mock', 'real', 'topic', 'wrongs', 'daily'] }).notNull(),
    topicId: text('topic_id').references(() => topics.id),
    questionIds: text('question_ids', { mode: 'json' }).$type<string[]>().notNull(),
    startedAt: integer('started_at', { mode: 'timestamp_ms' }).notNull().$defaultFn(() => new Date()),
    finishedAt: integer('finished_at', { mode: 'timestamp_ms' }),
    correct: integer('correct'),
    wrong: integer('wrong'),
    durationSec: integer('duration_sec'),
  },
  (t) => [index('idx_exams_user').on(t.userId, t.startedAt)],
);

export const lessons = sqliteTable('lessons', {
  id: text('id').primaryKey(),
  kind: text('kind', { enum: ['theory', 'driving'] }).notNull(),
  chapter: text('chapter').notNull(),
  title: text('title').notNull(),
  minutes: integer('minutes').notNull(),
  isPremium: integer('is_premium', { mode: 'boolean' }).notNull().default(false),
  videoUrl: text('video_url'), // harici, herkese açık adres (isteğe bağlı)
  videoKey: text('video_key'), // depolamadaki nesne anahtarı; istemciye süreli imzalı URL olarak verilir
  sort: integer('sort').notNull().default(0),
});

export const lessonProgress = sqliteTable(
  'lesson_progress',
  {
    userId: text('user_id').notNull().references(() => users.id, { onDelete: 'cascade' }),
    lessonId: text('lesson_id').notNull().references(() => lessons.id),
    positionSec: integer('position_sec').notNull().default(0),
    completed: integer('completed', { mode: 'boolean' }).notNull().default(false),
    updatedAt: integer('updated_at', { mode: 'timestamp_ms' }).notNull().$defaultFn(() => new Date()),
  },
  (t) => [primaryKey({ columns: [t.userId, t.lessonId] })],
);

export type Checkpoint = { title: string; detail: string; lat: number; lng: number };

export const examRoutes = sqliteTable(
  'exam_routes',
  {
    id: text('id').primaryKey(),
    city: text('city').notNull(),
    district: text('district').notNull(),
    name: text('name').notNull(),
    distanceKm: real('distance_km').notNull(),
    isPremium: integer('is_premium', { mode: 'boolean' }).notNull().default(false),
    path: text('path', { mode: 'json' }).$type<[number, number][]>().notNull(), // [lat, lng]
    checkpoints: text('checkpoints', { mode: 'json' }).$type<Checkpoint[]>().notNull(),
    videoLessonId: text('video_lesson_id').references(() => lessons.id),
  },
  (t) => [index('idx_routes_city').on(t.city, t.district)],
);

// MARK: - Analitik

/** Uygulamadan gelen olaylar (ekran görüntüleme, sınav başlatma, oturum başı/sonu…) */
export const events = sqliteTable(
  'events',
  {
    id: id(),
    userId: text('user_id').references(() => users.id, { onDelete: 'cascade' }),
    deviceId: text('device_id').notNull(), // anonim kurulum kimliği; giriş öncesi olayları bağlar
    sessionId: text('session_id').notNull(),
    name: text('name').notNull(),
    props: text('props', { mode: 'json' }).$type<Record<string, string | number | boolean | null>>(),
    at: integer('at', { mode: 'timestamp_ms' }).notNull(),
    appVersion: text('app_version'),
  },
  (t) => [index('idx_events_at').on(t.at), index('idx_events_user').on(t.userId, t.at), index('idx_events_session').on(t.sessionId)],
);

/** Soru hata bildirimleri */
export const questionReports = sqliteTable('question_reports', {
  id: id(),
  questionId: text('question_id').notNull().references(() => questions.id, { onDelete: 'cascade' }),
  userId: text('user_id').references(() => users.id, { onDelete: 'set null' }),
  message: text('message').notNull(),
  resolved: integer('resolved', { mode: 'boolean' }).notNull().default(false),
  createdAt: createdAt(),
});

/** Küçük anahtar-değer tablosu (ör. seed içeriğinin özeti) */
export const appMeta = sqliteTable('app_meta', {
  key: text('key').primaryKey(),
  value: text('value').notNull(),
});
