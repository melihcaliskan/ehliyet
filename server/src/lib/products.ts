/** Uygulamanın satın alma ürünleri. iOS'taki Products.storekit ve App Store Connect ile aynı olmalı. */

export type Scope = 'exams' | 'videos' | 'routes' | 'no_ads';

type Product = {
  kind: 'auto_renewable' | 'non_renewing' | 'non_consumable';
  scopes: Scope[];
  /** Yenilenmeyen abonelikte süreyi Apple vermez, biz hesaplarız */
  durationMonths?: number;
};

const ALL: Scope[] = ['exams', 'videos', 'routes', 'no_ads'];

export const PRODUCTS: Record<string, Product> = {
  'com.melihcaliskan.ehliyet.premium.monthly': { kind: 'auto_renewable', scopes: ALL },
  'com.melihcaliskan.ehliyet.premium.6months': { kind: 'non_renewing', scopes: ALL, durationMonths: 6 },
  'com.melihcaliskan.ehliyet.videos': { kind: 'non_consumable', scopes: ['videos'] },
};

export function expiryFor(productId: string, purchasedAt: Date, appleExpires?: number): Date | null {
  const p = PRODUCTS[productId];
  if (!p) return null;
  if (p.kind === 'auto_renewable') return appleExpires ? new Date(appleExpires) : null;
  if (p.kind === 'non_renewing') {
    const d = new Date(purchasedAt);
    d.setMonth(d.getMonth() + (p.durationMonths ?? 0));
    return d;
  }
  return null;
}
