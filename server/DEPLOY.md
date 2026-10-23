# Vercel'e yayınlama

Sunucu Vercel'de tek bir fonksiyon olarak çalışır (Fastify, sıfır yapılandırma). Adres: **https://ehliyet-api.melihcaliskan.com**

> Vercel'in ücretsiz **Hobby** planı ticari olmayan kullanım içindir. Geliştirme ve TestFlight için uygundur; App Store'da satış başlamadan önce **Pro**'ya geçin veya başka bir platforma taşıyın. Taşımak için yalnızca `ehliyet-api` DNS kaydını yeni adrese yönlendirmek yeter, uygulama güncellemesi gerekmez.

## 1. Turso veritabanı

```bash
brew install tursodatabase/tap/turso
turso auth login
turso db locations                      # Frankfurt'a en yakın bölgeyi seç
turso db create ehliyet --location <bölge>
turso db show ehliyet --url             # → DATABASE_URL
turso db tokens create ehliyet          # → DATABASE_AUTH_TOKEN
```

Tablolar ve içerik (sorular, harçlar…) sunucu ilk açıldığında otomatik oluşturulur.

## 2. Vercel projesi

Vercel CLI 48.6 veya üstü gerekir.

```bash
npm i -g vercel
cd server
vercel link            # yeni proje: "ehliyet-api"
```

Git ile bağlarsan: Vercel › Project › Settings › General › **Root Directory = `server`**.

## 3. Ortam değişkenleri

Vercel › Project › Settings › **Environment Variables** (Production):

| Değişken | Değer |
|---|---|
| `DATABASE_URL` | `libsql://ehliyet-<kullanıcı>.turso.io` |
| `DATABASE_AUTH_TOKEN` | Turso token'ı |
| `JWT_SECRET` | `openssl rand -base64 48` çıktısı (yereldekinden **farklı**) |
| `ADMIN_EMAILS` | `mlhclskn@gmail.com` |
| `APPLE_BUNDLE_ID` | `com.melihcaliskan.ehliyet` |
| `APPLE_ENVIRONMENT` | TestFlight için `Sandbox`, App Store için `Production` |
| `APPLE_APP_APPLE_ID` | App Store Connect › App Information › Apple ID (Production'da zorunlu) |
| `APPLE_ROOT_CERTS_BASE64` | `curl -sO https://www.apple.com/certificateauthority/AppleRootCA-G3.cer && base64 -i AppleRootCA-G3.cer` |
| `STORAGE_ENDPOINT` | `https://<ACCOUNT_ID>.r2.cloudflarestorage.com` |
| `STORAGE_BUCKET` | `ehliyet-videos` |
| `STORAGE_ACCESS_KEY_ID` / `STORAGE_SECRET_ACCESS_KEY` | R2 API token'ı |

## 4. Yayınla

```bash
vercel deploy --prod
```

Kontrol: `https://<proje>.vercel.app/health` → `{"ok":true}`

## 5. Alan adı

Vercel › Project › Settings › **Domains** › `ehliyet-api.melihcaliskan.com` ekle.

- `melihcaliskan.com` zaten Vercel'deyse kayıt otomatik eklenir.
- Değilse alan adını aldığın yerin DNS panelinde: **CNAME** · ad `ehliyet-api` · değer `cname.vercel-dns.com`

Ana site (`melihcaliskan.com`) etkilenmez.

## 6. Apple

App Store Connect › Uygulama › **App Information** › App Store Server Notifications:

- Production URL: `https://ehliyet-api.melihcaliskan.com/v1/iap/notifications`
- Sandbox URL: aynısı
- Sürüm: **Version 2**

Gizlilik politikası URL'si: `https://ehliyet-api.melihcaliskan.com/legal/privacy` (yayından önce `legal/` altındaki taslakları doldur).

## 7. Yönetim paneli

1. Uygulamada `mlhclskn@gmail.com` ile hesap aç (e-posta ve şifre).
2. `https://ehliyet-api.melihcaliskan.com/admin` adresinden aynı bilgilerle giriş yap.

## Notlar

- **Bölge:** Fonksiyon Frankfurt'ta (`fra1`) çalışır. Turso veritabanını da Frankfurt'a yakın seç, yoksa her sorgu gecikir.
- **İstek sınırlama:** Sunucunun kendi sınırı her Vercel örneğinde ayrı tutulur. Kaba kuvvet girişlere karşı Vercel › Firewall › **Rate Limiting** ile `/v1/auth/*` için ek kural koy.
- **Loglar:** Vercel › Project › Logs.
- **Geri alma:** Vercel › Deployments › önceki sürüm › **Instant Rollback**.
