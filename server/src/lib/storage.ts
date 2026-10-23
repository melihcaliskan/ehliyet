import { createReadStream, statSync } from 'node:fs';
import { GetObjectCommand, HeadObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import type { Config } from '../config.ts';

/**
 * Video depolama. S3 uyumlu her servisle çalışır; varsayılan hedef Cloudflare R2
 * (10 GB ücretsiz alan, trafik/egress ücreti yok).
 *
 * Videolar herkese açık değildir: sunucu yalnızca izleme hakkı olan kullanıcıya
 * kısa süreli imzalı URL verir. Link paylaşılsa bile süresi dolunca çalışmaz.
 */
export interface VideoStorage {
  signedUrl(key: string): Promise<string>;
}

export function createVideoStorage(config: Config): VideoStorage | null {
  const { STORAGE_ENDPOINT, STORAGE_BUCKET, STORAGE_ACCESS_KEY_ID, STORAGE_SECRET_ACCESS_KEY } = config;
  if (!STORAGE_ENDPOINT || !STORAGE_BUCKET || !STORAGE_ACCESS_KEY_ID || !STORAGE_SECRET_ACCESS_KEY) return null;

  const client = makeClient(config);
  return {
    signedUrl: (key) =>
      getSignedUrl(client, new GetObjectCommand({ Bucket: STORAGE_BUCKET, Key: key }), { expiresIn: config.VIDEO_URL_TTL_SEC }),
  };
}

export function makeClient(config: Config) {
  return new S3Client({
    region: config.STORAGE_REGION,
    endpoint: config.STORAGE_ENDPOINT,
    credentials: { accessKeyId: config.STORAGE_ACCESS_KEY_ID!, secretAccessKey: config.STORAGE_SECRET_ACCESS_KEY! },
  });
}

/** `npm run video:upload` betiği için */
export async function uploadFile(config: Config, key: string, path: string) {
  const client = makeClient(config);
  await client.send(
    new PutObjectCommand({
      Bucket: config.STORAGE_BUCKET,
      Key: key,
      Body: createReadStream(path),
      ContentLength: statSync(path).size,
      ContentType: 'video/mp4',
      CacheControl: 'private, max-age=31536000',
    }),
  );
  const head = await client.send(new HeadObjectCommand({ Bucket: config.STORAGE_BUCKET, Key: key }));
  return head.ContentLength ?? 0;
}
