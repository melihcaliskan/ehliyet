# Ehliyet Sunucu

Node.js (≥24) + TypeScript + Fastify + Zod + **Turso (libSQL) + Drizzle ORM**. Derleme adımı yok; Node TS dosyalarını doğrudan çalıştırır.

Veritabanı: canlıda Turso (`DATABASE_URL=libsql://…` + `DATABASE_AUTH_TOKEN`). Yerelde aynı istemci `file:` URL'siyle Turso hesabı olmadan çalışır; testler `:memory:` kullanır. Migration'lar açılışta otomatik uygulanır.

```bash
cp .env.example .env   # JWT_SECRET'ı değiştir
npm install
npm run dev            # http://localhost:3000
npm test
npm run typecheck
npm run db:generate   # şema değişince yeni migration üret
```

Turso kurulumu:

```bash
turso db create ehliyet
turso db show ehliyet --url        # → DATABASE_URL
turso db tokens create ehliyet     # → DATABASE_AUTH_TOKEN
```

## Uç noktalar

| Yöntem | Yol | Auth | Açıklama |
|---|---|---|---|
| POST | `/v1/auth/register` | – | `{email, password, name?}` → `{accessToken, refreshToken, user}` |
| POST | `/v1/auth/login` | – | `{email, password}` |
| POST | `/v1/auth/apple` | – | `{identityToken, name?}` — Sign in with Apple |
| POST | `/v1/auth/refresh` | – | `{refreshToken}` → yeni çift (rotasyonlu) |
| POST | `/v1/auth/logout` | – | `{refreshToken}` |
| GET | `/v1/auth/me` | ✓ | Kullanıcı + `premium` durumu |
| DELETE | `/v1/auth/me` | ✓ | Hesap silme (App Store zorunluluğu) |
| GET | `/v1/fees?class=B&includeCourse=true` | – | Harç/ücret bölümleri ve toplam (kuruş) |
| GET | `/v1/fees/classes` | – | Ehliyet sınıfları |
| GET | `/v1/calendar/sessions?month=2026-11&kind=e_sinav` | – | Resmi sınav oturumları |
| GET/POST | `/v1/calendar/appointments` | ✓ | Kullanıcının randevuları |
| PATCH/DELETE | `/v1/calendar/appointments/:id` | ✓ | |
| GET | `/v1/study/topics` | – | Konular ve soru sayıları |
| GET | `/v1/study/progress` | ✓ | Konu ilerlemesi, yanlış sayısı, kalan ücretsiz deneme |
| POST | `/v1/study/exams` | ✓ | `{kind: mock \| topic \| wrongs, topicId?}`; ücretsiz kullanıcıya 3 deneme, sonra 402 |
| POST | `/v1/study/exams/:id/answers` | ✓ | `{questionId, choice}` — her cevap anında kaydedilir |
| POST | `/v1/study/exams/:id/finish` | ✓ | `{durationSec}` → puan, doğru/yanlış |
| GET | `/v1/study/exams` | ✓ | Sınav geçmişi |
| GET | `/v1/study/wrong-answers` | ✓ | Son cevabı yanlış olan sorular |
| GET | `/v1/lessons?kind=theory` | opsiyonel | Dersler; kilitli dersin `videoUrl`'i gönderilmez |
| PUT | `/v1/lessons/:id/progress` | ✓ | `{positionSec}`; %90'da tamamlandı sayılır |
| GET | `/v1/routes/cities` | – | İl ve ilçeler |
| GET | `/v1/routes?city=İstanbul` | opsiyonel | Güzergahlar; premium olanın rotası kilitli |
| GET | `/v1/notifications` | ✓ | Randevu, seri ve sonuç bildirimleri |
| GET | `/v1/search?q=park` | – | Soru ve ders araması |
| GET | `/v1/iap/entitlements` | ✓ | Aktif haklar (`isPremium`, `scopes`) |
| POST | `/v1/iap/transactions` | ✓ | `{signedTransaction}` — StoreKit 2 `jwsRepresentation` |
| POST | `/v1/iap/restore` | ✓ | `{signedTransactions: []}` — `Transaction.currentEntitlements` |
| POST | `/v1/iap/notifications` | Apple imzası | App Store Server Notifications v2 |

## In-app purchase

Ürünler [src/lib/products.ts](src/lib/products.ts) içinde; iOS'taki `Products.storekit` ve App Store Connect ile aynı olmalı:

| Ürün | Tür | Hak |
|---|---|---|
| `…premium.monthly` | Otomatik yenilenen | Hepsi |
| `…premium.6months` | Yenilenmeyen (süreyi sunucu hesaplar) | Hepsi, 6 ay |
| `…videos` | Tek seferlik | Yalnızca videolar |

- Her JWS, `@apple/app-store-server-library` ile Apple kök sertifikasına kadar doğrulanır; bundle id ve ortam kontrol edilir.
- iOS `appAccountToken = user.id` gönderir; başka hesaba ait bir işlem 403 döner.
- Yenileme, iade ve iptal `/v1/iap/notifications` üzerinden işlenir.

Canlıya çıkmadan önce:
1. `certs/` klasörüne Apple kök sertifikalarını koy (https://www.apple.com/certificateauthority/ → `AppleRootCA-G3.cer`).
2. `APPLE_ENVIRONMENT=Sandbox` (TestFlight) veya `Production` + `APPLE_APP_APPLE_ID`.
3. App Store Connect › App Information › App Store Server Notifications: Production ve Sandbox URL'si `https://<sunucu>/v1/iap/notifications`, sürüm 2.

`APPLE_ENVIRONMENT=Xcode` yerel StoreKit testine göredir; Xcode'un imzaladığı işlemler kök sertifika gerektirmez.

## Videolar (Cloudflare R2)

Videolar herkese açık değil: sunucu yalnızca izleme hakkı olan kullanıcıya **4 saat geçerli imzalı URL** verir.
R2 S3 uyumlu olduğu için Backblaze B2, Wasabi veya Google Cloud Storage'a da yalnızca `.env` değiştirilerek geçilebilir.

Neden R2: 10 GB ücretsiz alan ve **izlenme (egress) ücreti yok**. Firebase Storage artık ücretsiz Spark planında yok, Blaze (kart tanımlı) plan istiyor; video trafiği de ücretli.

1. Cloudflare panel › R2 › **Create bucket** (`ehliyet-videos`).
2. R2 › **Manage API tokens** › *Object Read & Write*, yalnızca bu bucket.
3. `.env` içinde `STORAGE_ENDPOINT=https://<ACCOUNT_ID>.r2.cloudflarestorage.com`, anahtarlar ve bucket adı.
4. Videoları yükle (MP4, H.264, 720p önerilir; 10 dakikalık ders yaklaşık 60–100 MB):

```bash
npm run video:upload -- t1 ./videolar/trafige-giris.mp4
```

Depolama ayarlanmamışsa dersler listelenir ama video adresi boş gelir.
