import { z } from 'zod';

const schema = z.object({
  PORT: z.coerce.number().default(3000),
  HOST: z.string().default('0.0.0.0'),
  // Turso: libsql://<db>-<org>.turso.io  ·  yerel: file:./data/ehliyet.db  ·  test: :memory:
  DATABASE_URL: z.string().default('file:./data/ehliyet.db'),
  DATABASE_AUTH_TOKEN: z.string().optional(),
  JWT_SECRET: z.string().min(32, 'JWT_SECRET en az 32 karakter olmalı'),
  ACCESS_TOKEN_TTL: z.string().default('15m'),
  REFRESH_TOKEN_DAYS: z.coerce.number().default(60),
  APPLE_BUNDLE_ID: z.string().default('com.melihcaliskan.ehliyet'),
  // App Store işlem doğrulaması
  APPLE_ENVIRONMENT: z.enum(['Production', 'Sandbox', 'Xcode', 'LocalTesting']).default('Sandbox'),
  APPLE_APP_APPLE_ID: z.coerce.number().optional(), // Production için zorunlu (App Store Connect › App Information)
  APPLE_ROOT_CERTS_DIR: z.string().default('./certs'), // AppleRootCA-G3.cer vb.
  // Serverless ortamlar için alternatif: sertifikaların base64 hâli, virgülle ayrılmış
  APPLE_ROOT_CERTS_BASE64: z.string().optional(),
  // Video depolama (Cloudflare R2 veya başka bir S3 uyumlu servis)
  // R2: https://<ACCOUNT_ID>.r2.cloudflarestorage.com, region "auto"
  STORAGE_ENDPOINT: z.url().optional(),
  STORAGE_REGION: z.string().default('auto'),
  STORAGE_BUCKET: z.string().optional(),
  STORAGE_ACCESS_KEY_ID: z.string().optional(),
  STORAGE_SECRET_ACCESS_KEY: z.string().optional(),
  VIDEO_URL_TTL_SEC: z.coerce.number().default(4 * 3600),
  // Bu e-postalarla giriş yapanlar yönetim paneline erişir (virgülle ayrılmış)
  ADMIN_EMAILS: z.string().optional(),
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
});

export type Config = z.infer<typeof schema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = schema.safeParse(env);
  if (!parsed.success) {
    throw new Error('Geçersiz ortam değişkenleri:\n' + z.prettifyError(parsed.error));
  }
  const config = parsed.data;
  if (config.APPLE_ENVIRONMENT === 'Production' && !config.APPLE_APP_APPLE_ID) {
    throw new Error('APPLE_ENVIRONMENT=Production için APPLE_APP_APPLE_ID gerekli');
  }
  return config;
}
