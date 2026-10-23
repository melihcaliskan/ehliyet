import type { examRoutes, lessons, questions, topics } from './schema.ts';

// Tasarımdaki örnek içerik. Gerçek soru bankası ve videolar eklendiğinde buradan değil,
// bir yönetim aracından veya içe aktarma betiğinden yüklenmeli.

export const TOPICS: (typeof topics.$inferInsert)[] = [
  { id: 'trafik', name: 'Trafik ve Çevre', icon: 'car.fill', color: '#0062CC', sort: 0 },
  { id: 'ilkyardim', name: 'İlk Yardım', icon: 'cross.case.fill', color: '#D70015', sort: 1 },
  { id: 'motor', name: 'Motor ve Araç Tekniği', icon: 'engine.combustion.fill', color: '#C93400', sort: 2 },
  { id: 'adab', name: 'Trafik Adabı', icon: 'hand.raised.fill', color: '#248A3D', sort: 3 },
];

export { QUESTION_BANK as QUESTIONS } from './questions.ts';

const L = (id: string, kind: 'theory' | 'driving', chapter: string, title: string, minutes: number, isPremium: boolean, sort: number) =>
  ({ id, kind, chapter, title, minutes, isPremium, sort, videoKey: `lessons/${id}.mp4` }) satisfies typeof lessons.$inferInsert;

export const LESSONS: (typeof lessons.$inferInsert)[] = [
  L('t1', 'theory', 'Trafik ve Çevre Bilgisi', 'Trafiğe giriş', 12, false, 1),
  L('t2', 'theory', 'Trafik ve Çevre Bilgisi', 'Yol çizgileri', 10, false, 2),
  L('t3', 'theory', 'Trafik ve Çevre Bilgisi', 'Tehlike uyarı işaretleri', 15, false, 3),
  L('t4', 'theory', 'Trafik ve Çevre Bilgisi', 'Trafik tanzim işaretleri', 13, false, 4),
  L('t5', 'theory', 'Trafik ve Çevre Bilgisi', 'Bilgi işaretleri', 9, false, 5),
  L('t6', 'theory', 'Trafik ve Çevre Bilgisi', 'Uyarı levhaları', 14, false, 6),
  L('t7', 'theory', 'Trafik ve Çevre Bilgisi', 'Kavşaklarda geçiş hakkı', 18, false, 7),
  L('t8', 'theory', 'Trafik ve Çevre Bilgisi', 'Hız sınırları ve takip mesafesi', 11, true, 8),
  L('t9', 'theory', 'Trafik ve Çevre Bilgisi', 'Sollama kuralları', 12, true, 9),
  L('d1', 'driving', 'Direksiyon', 'Araç kontrolleri ve ayarlar', 7, false, 1),
  L('d2', 'driving', 'Direksiyon', 'Rampa kalkışı', 10, false, 2),
  L('d3', 'driving', 'Direksiyon', 'Paralel park adım adım', 9, true, 3),
  L('d4', 'driving', 'Direksiyon', 'Geri geri park ve manevra', 12, true, 4),
];

export const ROUTES: (typeof examRoutes.$inferInsert)[] = [
  {
    id: 'ist-kadikoy', city: 'İstanbul', district: 'Kadıköy', name: 'Kadıköy Sınav Alanı', distanceKm: 4.2, isPremium: false, videoLessonId: 'd2',
    path: [[40.996, 29.02], [40.996, 29.03], [40.988, 29.03], [40.988, 29.04], [40.98, 29.04]],
    checkpoints: [
      { title: 'Rampa kalkışı', detail: 'El freniyle kalkış', lat: 40.996, lng: 29.03 },
      { title: 'Kavşak', detail: 'Sola dönüş, geçiş hakkı', lat: 40.988, lng: 29.03 },
      { title: 'Park', detail: 'Yol kenarına paralel park', lat: 40.988, lng: 29.04 },
    ],
  },
  {
    id: 'ist-uskudar', city: 'İstanbul', district: 'Üsküdar', name: 'Üsküdar Sınav Alanı', distanceKm: 3.8, isPremium: true, videoLessonId: 'd3',
    path: [[41.026, 29.015], [41.026, 29.025], [41.02, 29.025], [41.02, 29.035]],
    checkpoints: [
      { title: 'Okul geçidi', detail: 'Yavaşlama ve yaya önceliği', lat: 41.026, lng: 29.025 },
      { title: 'Dönel kavşak', detail: 'Şerit seçimi', lat: 41.02, lng: 29.025 },
      { title: 'Park', detail: 'Geri geri park', lat: 41.02, lng: 29.035 },
    ],
  },
  {
    id: 'ank-cankaya', city: 'Ankara', district: 'Çankaya', name: 'Çankaya Sınav Alanı', distanceKm: 5.1, isPremium: true, videoLessonId: 'd3',
    path: [[39.91, 32.85], [39.91, 32.86], [39.9, 32.86], [39.9, 32.87]],
    checkpoints: [
      { title: 'Şerit değiştirme', detail: 'Ayna ve sinyal', lat: 39.91, lng: 32.86 },
      { title: 'Işıklı kavşak', detail: 'Sağa dönüş', lat: 39.9, lng: 32.86 },
      { title: 'Park', detail: 'Paralel park', lat: 39.9, lng: 32.87 },
    ],
  },
];
