import type { FastifyInstance } from 'fastify';

// Sınav kuralları içeriği. MEB yönetmeliği değiştiğinde güncellenip UPDATED_AT ilerletilmeli.
const UPDATED_AT = '2026-10-23';

const rules = {
  updatedAt: UPDATED_AT,
  rights: [
    { id: 'e_sinav', title: 'E-SINAV', value: '4', total: 4, remaining: 4, detail: '50 soru · 45 dk\nGeçme: 70 puan' },
    { id: 'direksiyon', title: 'DİREKSİYON', value: '4+4', total: 4, remaining: 3, detail: '40 dk · Geçme: 70 puan\nİkinci 4 hak nakille' },
  ],
  sections: [
    {
      id: 'e_sinav',
      title: 'E-Sınav adım adım',
      steps: [
        { title: 'Erken git', detail: 'Kimlik kartınla sınav saatinden önce sınav merkezinde ol.' },
        { title: 'Eşyalarını bırak', detail: 'Telefon, akıllı saat ve çantanı salona sokma.' },
        { title: '50 soruyu çöz', detail: '45 dakikan var. Cevaplarını bilgisayar ekranında işaretle.' },
        { title: 'Sonucunu öğren', detail: '100 üzerinden en az 70 puan alırsan direksiyon sınavına geçersin.' },
      ],
    },
    {
      id: 'direksiyon',
      title: 'Direksiyon sınavı adım adım',
      steps: [
        { title: 'Araç bilgisi soruları', detail: 'Sınav, aracın donanımıyla ilgili sorularla başlar.' },
        { title: 'Hazırlan ve kalk', detail: 'Koltuğu, aynaları ve kemeri ayarla. Aracı çalıştırıp güvenle hareket et.' },
        { title: 'Güzergahta sür', detail: 'Onaylı güzergahta hız sınırına, işaretlere ve geçiş hakkına uy.' },
        { title: 'Manevralar', detail: "En az 25 m geri git, 30 km/s'de ani duruş yap, 90° geri dönüş yap." },
        { title: 'Geri park', detail: 'Dubaların arasına yola paralel olarak geri geri park et.' },
        { title: 'Değerlendirme', detail: 'Sınav yaklaşık 40 dakika sürer. 100 üzerinden en az 70 puan gerekir.' },
      ],
    },
  ],
  // **kalın** işaretli kısımlar istemcide kalın gösterilir
  facts: [
    { icon: 'retry', warning: false, text: 'Geri parkta dubaların arasından tek hamlede geçemezsen aynı hamleyi **bir kez daha** deneyebilirsin.' },
    { icon: 'transfer', warning: false, text: 'İlk 4 direksiyon hakkın biterse başka bir kursa nakil olarak **4 hak daha** kullanabilirsin.' },
    { icon: 'calendar', warning: false, text: 'Direksiyondan kalıp **3 yıl içinde** yeniden kayıt olursan teorik eğitimi ve e-sınavı tekrar etmezsin.' },
    { icon: 'alert', warning: false, text: 'Komisyon aracı güvenle kullanamayacağına karar verirse sınav **erken bitirilebilir**.' },
    { icon: 'ban', warning: true, text: 'Başkasının yerine sınava giren ya da girmeye çalışan **5 yıl** boyunca sınavlara alınmaz.' },
  ],
  note: 'Kurallar MEB yönetmeliğine göre değişebilir.',
};

export async function ruleRoutes(app: FastifyInstance) {
  app.get('/', async (_req, reply) => {
    reply.header('Cache-Control', 'public, max-age=86400');
    return rules;
  });
}
