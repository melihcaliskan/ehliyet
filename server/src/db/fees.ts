import type { feeItems } from './schema.ts';

/**
 * 2026 sürücü belgesi harç ve ücretleri. Tutarlar kuruş cinsinden.
 *
 * Ocak 2026 tarifesi (yeniden değerleme oranıyla): hesapkurdu.com, 25.03.2026 güncellemesi.
 * Haziran 2026 tarifesi: Sözcü (11.06.2026) ve İstiklal (12.06.2026) haberleri. Bu kaynaklar yalnızca
 * B sınıfını veriyor; tüm kalemler Ocak'a göre tam %40 arttığı için diğer sınıflar aynı oranla
 * hesaplandı ve `isEstimate` olarak işaretlendi. Resmi tarife (Harçlar Kanunu 4 sayılı tarife)
 * yayımlanınca doğrulanmalı.
 */

type Fee = typeof feeItems.$inferInsert;

const GROUPS = [
  { key: 'a', classes: ['A1', 'A2', 'A', 'F'], harc: 223990 },
  { key: 'b', classes: ['B'], harc: 675460 },
  { key: 'agir', classes: ['BE', 'C', 'D'], harc: 1127120 },
] as const;

const JAN = { validFrom: '2026-01-01', kagit: 169000, vakif: 42500, source: 'hesapkurdu.com · 25.03.2026' };
const JUN = { validFrom: '2026-06-01', factor: 1.4, source: 'Sözcü / İstiklal · Haziran 2026' };

// Kurs ve sınav kalemleri (İstiklal, 12.06.2026; B sınıfı ilk seferde geçme varsayımıyla)
const COURSE: Omit<Fee, 'validFrom' | 'sort'>[] = [
  { id: 'kurs', category: 'course', title: 'Kurs ücreti (taban)', amountKurus: 2500000, licenseClass: 'B', isCourseFee: true },
  { id: 'e-sinav', category: 'course', title: 'E-sınav ücreti', amountKurus: 125000 },
  { id: 'direksiyon-sinavi', category: 'course', title: 'Direksiyon sınavı', amountKurus: 280000 },
  { id: 'saglik-raporu', category: 'course', title: 'Sağlık raporu (ort.)', amountKurus: 31200 },
  { id: 'biyometrik-foto', category: 'course', title: 'Biyometrik fotoğraf (ort.)', amountKurus: 50000 },
];

function tariff(validFrom: string, factor: number, source: string, estimateExceptB: boolean): Fee[] {
  const r = (k: number) => Math.round(k * factor);
  const rows: Fee[] = [];
  for (const g of GROUPS) {
    for (const cls of g.classes) {
      rows.push({
        id: `${validFrom}:harc:${cls}`, category: 'state', title: 'Sürücü belgesi harcı', amountKurus: r(g.harc),
        licenseClass: cls, sort: 0, validFrom, source, isEstimate: estimateExceptB && cls !== 'B',
      });
    }
  }
  rows.push(
    { id: `${validFrom}:kagit`, category: 'state', title: 'Değerli kâğıt bedeli', amountKurus: r(JAN.kagit), sort: 1, validFrom, source },
    { id: `${validFrom}:vakif`, category: 'state', title: 'Vakıf payı', amountKurus: r(JAN.vakif), sort: 2, validFrom, source },
  );
  COURSE.forEach((c, i) => rows.push({ ...c, id: `${validFrom}:${c.id}`, sort: 10 + i, validFrom, source: 'İstiklal · 12.06.2026' }));
  return rows;
}

export const FEES: Fee[] = [...tariff(JAN.validFrom, 1, JAN.source, false), ...tariff(JUN.validFrom, JUN.factor, JUN.source, true)];
