import { eq } from 'drizzle-orm';
import type { JWSTransactionDecodedPayload } from '@apple/app-store-server-library';
import type { DB } from '../db/index.ts';
import { purchases } from '../db/schema.ts';
import { PRODUCTS, expiryFor, type Scope } from './products.ts';

export type Entitlements = {
  isPremium: boolean;
  scopes: Scope[];
  active: { productId: string; expiresAt: string | null; environment: string }[];
};

export async function getEntitlements(db: DB, userId: string): Promise<Entitlements> {
  const now = new Date();
  const rows = await db.select().from(purchases).where(eq(purchases.userId, userId));
  const active = rows.filter((r) => !r.revokedAt && (!r.expiresAt || r.expiresAt > now) && PRODUCTS[r.productId]);
  const scopes = [...new Set(active.flatMap((r) => PRODUCTS[r.productId]!.scopes))];
  return {
    isPremium: scopes.includes('exams'),
    scopes,
    active: active.map((r) => ({ productId: r.productId, expiresAt: r.expiresAt?.toISOString() ?? null, environment: r.environment })),
  };
}

export class PurchaseError extends Error {
  statusCode: number;
  code: string;
  constructor(code: string, message: string, statusCode = 400) {
    super(message);
    this.code = code;
    this.statusCode = statusCode;
  }
}

/**
 * Doğrulanmış bir işlemi kaydeder ya da günceller (yenileme, iade, iptal).
 * `userId` verilmezse (sunucu bildirimi) kullanıcı appAccountToken'dan veya önceki kayıttan bulunur.
 */
export async function applyTransaction(db: DB, tx: JWSTransactionDecodedPayload, userId?: string) {
  if (!tx.transactionId || !tx.originalTransactionId || !tx.productId || !tx.purchaseDate) {
    throw new PurchaseError('invalid_transaction', 'İşlem eksik alan içeriyor');
  }
  if (!PRODUCTS[tx.productId]) throw new PurchaseError('unknown_product', `Bilinmeyen ürün: ${tx.productId}`);

  // Satın alma bu kullanıcıya mı ait? iOS tarafı appAccountToken = user.id gönderiyor
  if (userId && tx.appAccountToken && tx.appAccountToken.toLowerCase() !== userId.toLowerCase()) {
    throw new PurchaseError('account_mismatch', 'Bu satın alma başka bir hesaba ait', 403);
  }

  let owner = userId ?? tx.appAccountToken?.toLowerCase();
  if (!owner) {
    const prev = await db.query.purchases.findFirst({ where: eq(purchases.originalTransactionId, tx.originalTransactionId) });
    owner = prev?.userId ?? undefined;
  }

  const purchasedAt = new Date(tx.purchaseDate);
  const values = {
    userId: owner ?? null,
    productId: tx.productId,
    transactionId: tx.transactionId,
    originalTransactionId: tx.originalTransactionId,
    environment: String(tx.environment ?? 'Unknown'),
    purchasedAt,
    expiresAt: expiryFor(tx.productId, purchasedAt, tx.expiresDate),
    revokedAt: tx.revocationDate ? new Date(tx.revocationDate) : null,
  };

  // Aynı işlem başka bir kullanıcıya zaten bağlıysa (hesap paylaşımı) sahipliği değiştirme
  const existing = await db.query.purchases.findFirst({ where: eq(purchases.transactionId, tx.transactionId) });
  if (existing?.userId && userId && existing.userId !== userId) {
    throw new PurchaseError('account_mismatch', 'Bu satın alma başka bir hesaba ait', 403);
  }

  await db
    .insert(purchases)
    .values(values)
    .onConflictDoUpdate({
      target: purchases.transactionId,
      set: { expiresAt: values.expiresAt, revokedAt: values.revokedAt, userId: existing?.userId ?? values.userId },
    });

  return owner ?? null;
}
