import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { getEntitlements, applyTransaction, PurchaseError } from '../lib/entitlements.ts';
import type { AppStoreVerifier } from '../lib/appstore.ts';

const transactionBody = z.object({
  // StoreKit 2: VerificationResult<Transaction>.jwsRepresentation
  signedTransaction: z.string().min(10),
});
const restoreBody = z.object({ signedTransactions: z.array(z.string().min(10)).max(100) });
const notificationBody = z.object({ signedPayload: z.string() });

export async function iapRoutes(app: FastifyInstance, opts: { verifier: AppStoreVerifier }) {
  const { db } = app;
  const { verifier } = opts;

  const verify = async (jws: string) => {
    try {
      return await verifier.verifyTransaction(jws);
    } catch (err) {
      app.log.warn({ err }, 'App Store işlemi doğrulanamadı');
      throw new PurchaseError('invalid_signature', 'Satın alma doğrulanamadı', 400);
    }
  };

  app.register(async (priv) => {
    priv.addHook('preHandler', app.authenticate);

    priv.get('/entitlements', async (req) => getEntitlements(db, req.userId));

    /** Yeni satın alma veya Transaction.updates'ten gelen işlem */
    priv.post('/transactions', async (req) => {
      const { signedTransaction } = transactionBody.parse(req.body);
      await applyTransaction(db, await verify(signedTransaction), req.userId);
      return getEntitlements(db, req.userId);
    });

    /** "Satın Alımları Geri Yükle": Transaction.currentEntitlements listesi */
    priv.post('/restore', async (req) => {
      const { signedTransactions } = restoreBody.parse(req.body);
      for (const jws of signedTransactions) {
        try {
          await applyTransaction(db, await verify(jws), req.userId);
        } catch (err) {
          if (!(err instanceof PurchaseError)) throw err;
          req.log.warn({ code: err.code }, 'Geri yüklemede işlem atlandı');
        }
      }
      return getEntitlements(db, req.userId);
    });
  });

  /**
   * App Store Server Notifications v2. App Store Connect'te
   * "App Store Server Notifications" URL'si olarak https://<sunucu>/v1/iap/notifications girilmeli.
   * Yenileme, iade (REFUND), iptal (REVOKE) ve süre dolumu buradan işlenir.
   */
  app.post('/notifications', async (req, reply) => {
    const { signedPayload } = notificationBody.parse(req.body);
    let notification;
    try {
      notification = await verifier.verifyNotification(signedPayload);
    } catch (err) {
      req.log.warn({ err }, 'Geçersiz App Store bildirimi');
      return reply.code(400).send({ error: 'invalid_signature' });
    }

    const signedTx = notification.data?.signedTransactionInfo;
    req.log.info({ type: notification.notificationType, subtype: notification.subtype }, 'App Store bildirimi');
    if (signedTx) {
      try {
        await applyTransaction(db, await verifier.verifyTransaction(signedTx));
      } catch (err) {
        if (!(err instanceof PurchaseError)) throw err;
        req.log.warn({ code: err.code }, 'Bildirimdeki işlem atlandı');
      }
    }
    // 200 dönülmezse Apple bildirimi tekrar gönderir
    return reply.code(200).send();
  });
}
