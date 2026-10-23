import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  Environment,
  SignedDataVerifier,
  type JWSTransactionDecodedPayload,
  type ResponseBodyV2DecodedPayload,
} from '@apple/app-store-server-library';
import type { Config } from '../config.ts';

/** Testlerde sahte doğrulayıcı verilebilsin diye arayüz */
export interface AppStoreVerifier {
  verifyTransaction(jws: string): Promise<JWSTransactionDecodedPayload>;
  verifyNotification(signedPayload: string): Promise<ResponseBodyV2DecodedPayload>;
}

/**
 * Apple'ın imzaladığı JWS'leri sertifika zinciriyle (Apple Root CA'ya kadar) doğrular.
 * Kök sertifikalar: https://www.apple.com/certificateauthority/ → AppleRootCA-G3.cer (ve G2)
 */
export function createAppStoreVerifier(config: Config): AppStoreVerifier {
  let certs: Buffer[] = [];
  try {
    certs = readdirSync(config.APPLE_ROOT_CERTS_DIR)
      .filter((f) => f.endsWith('.cer'))
      .map((f) => readFileSync(join(config.APPLE_ROOT_CERTS_DIR, f)));
  } catch {
    // klasör yok; aşağıda kontrol ediliyor
  }
  if (config.APPLE_ROOT_CERTS_BASE64) {
    certs.push(...config.APPLE_ROOT_CERTS_BASE64.split(',').map((b) => Buffer.from(b.trim(), 'base64')));
  }

  const env = config.APPLE_ENVIRONMENT as Environment;
  // Xcode/LocalTesting ortamında işlemler yerel sertifikayla imzalanır, kök zinciri gerekmez
  const local = env === Environment.XCODE || env === Environment.LOCAL_TESTING;
  if (!local && certs.length === 0) {
    throw new Error(`Apple kök sertifikası bulunamadı (${config.APPLE_ROOT_CERTS_DIR}/*.cer veya APPLE_ROOT_CERTS_BASE64)`);
  }

  const verifier = new SignedDataVerifier(certs, !local, env, config.APPLE_BUNDLE_ID, config.APPLE_APP_APPLE_ID);
  return {
    verifyTransaction: (jws) => verifier.verifyAndDecodeTransaction(jws),
    verifyNotification: (payload) => verifier.verifyAndDecodeNotification(payload),
  };
}
