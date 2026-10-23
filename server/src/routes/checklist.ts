import type { FastifyInstance } from 'fastify';

/**
 * Direksiyon sınavı kontrol listesi. İçerik sunucuda tutulur ki uygulama güncellemesi
 * gerekmeden değiştirilebilsin. İşaretleme durumu cihazda saklanır.
 * Dayanak: MEB direksiyon sınavı uygulama ve değerlendirme kriterleri.
 */
const checklist = {
  updatedAt: '2026-10-23',
  sections: [
    {
      id: 'once',
      title: 'Sınavdan önce',
      icon: 'bag.fill',
      items: [
        { id: 'kimlik', title: 'Kimlik kartını yanına al', detail: 'Kimliksiz sınava alınmazsın.' },
        { id: 'gozluk', title: 'Gözlük veya lens', detail: 'Sağlık raporunda varsa sınavda takman zorunlu.' },
        { id: 'uyku', title: 'İyi uyu, erken git', detail: 'Sınav alanına en az 30 dakika önce ulaş.' },
        { id: 'ayakkabi', title: 'Rahat, düz tabanlı ayakkabı', detail: 'Pedalları hissetmeni kolaylaştırır.' },
      ],
    },
    {
      id: 'arac',
      title: 'Araca binince',
      icon: 'car.fill',
      items: [
        { id: 'cevre', title: 'Aracın çevresini kontrol et', detail: 'Lastikler, altı ve çevresinde engel var mı bak.' },
        { id: 'koltuk', title: 'Koltuğu ayarla', detail: 'Debriyaja tam bastığında dizin hafif bükük kalmalı.' },
        { id: 'direksiyon', title: 'Direksiyonu ve koltuk başlığını ayarla', detail: 'Başlığın üst kısmı göz hizanda olmalı.' },
        { id: 'aynalar', title: 'Üç aynayı ayarla', detail: 'İç ayna arka camı tam, yan aynalar aracın kenarını az göstermeli.' },
        { id: 'kemer', title: 'Emniyet kemerini tak', detail: 'Komisyonun göreceği şekilde, kalkıştan önce.' },
        { id: 'el-freni', title: 'El freni çekili, vites boşta', detail: 'Motoru çalıştırmadan önce kontrol et.' },
      ],
    },
    {
      id: 'surus',
      title: 'Sürüş sırasında',
      icon: 'steeringwheel',
      items: [
        { id: 'sinyal', title: 'Her manevrada sinyal ver', detail: 'Kalkışta, şerit değiştirirken, dönüşlerde ve park ederken.' },
        { id: 'ayna-kontrol', title: 'Sinyalden önce aynaya bak', detail: 'Ayna → sinyal → omuz kontrolü → manevra.' },
        { id: 'hiz', title: 'Hız sınırına ve levhalara uy', detail: 'Okul ve yaya geçitlerinde yavaşla.' },
        { id: 'yaya', title: 'Yayaya yol ver', detail: 'Yaya geçidinde bekleyen yaya varsa dur.' },
        { id: 'takip', title: 'Takip mesafesini koru', detail: 'Öndeki araçla aranda en az 2 saniye olsun.' },
      ],
    },
    {
      id: 'manevra',
      title: 'Manevralar',
      icon: 'arrow.triangle.turn.up.right.diamond.fill',
      items: [
        { id: 'rampa', title: 'Rampada geri kaçırmadan kalk', detail: 'El freni ve debriyaj kontrolüyle.' },
        { id: 'geri', title: 'En az 25 metre düz geri git', detail: 'Arkaya dönerek ve aynalardan kontrol ederek.' },
        { id: 'ani-durus', title: '30 km/s hızdayken güvenli duruş', detail: 'Aracı kaydırmadan, düz durdur.' },
        { id: 'donus', title: '90° geri dönüş', detail: 'Dubalara veya kaldırıma çarpmadan.' },
        { id: 'park', title: 'Dubalar arasına paralel geri park', detail: 'Geçemezsen aynı hamleyi bir kez daha deneyebilirsin.' },
      ],
    },
    {
      id: 'elenme',
      title: 'Sınavı doğrudan bitiren hatalar',
      icon: 'exclamationmark.octagon.fill',
      warning: true,
      items: [
        { id: 'kirmizi', title: 'Kırmızı ışıkta geçmek', detail: '' },
        { id: 'dur', title: '"DUR" levhasında durmamak', detail: '' },
        { id: 'yol-hakki', title: 'Geçiş hakkını ihlal etmek', detail: 'Yayaya veya ana yoldaki araca yol vermemek.' },
        { id: 'kaza', title: 'Kazaya sebep olmak veya komisyonun müdahale etmesi', detail: '' },
      ],
    },
  ],
};

export async function checklistRoutes(app: FastifyInstance) {
  app.get('/', async (_req, reply) => {
    reply.header('Cache-Control', 'public, max-age=3600');
    return checklist;
  });
}
