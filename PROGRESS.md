# İyileştirme İlerleme Takibi (v2 — Yapı Kontrolü + Faz 3)

> Önceki tüm fazlar (Faz 1: kritik hatalar/performans, Faz 2: mimari/CSS-JS
> pipeline) tamamlanmış ve doğrulanmıştır. Bu dosya, bu tarihten itibaren
> "TEK PARÇA TALİMAT" belgesindeki adımları takip eder.
> Her madde: [ ] yapılmadı · [~] devam ediyor · [x] tamam · [B] bloke

## Bölüm A — Eski Kalıntı Temizliği + Yapı Kontrolü + Faz 2 Kapanışı
- [x] Eski oturum kalıntıları temizlendi (A.0) — silinenler: **YOK**. `.emergent/`
  içindekiler (emergent.yml, system_deps.txt, markers/.bootstrap-complete,
  cron/*) çalışan platforma ait ve günceldir (webhook-crond servisi aktif
  kullanıyor) → dokunulmadı. `test_reports/` yalnızca `.gitkeep` içeriyordu
  (eski iteration_*.json yok). Tekrar eden laravel_project kopyası yok.
- [x] Klasör/git kontrolü çalıştırıldı (A.1) — 7 komut çalıştı.
- [x] Sonuç: **Durum 1 — yapı zaten temiz.** laravel_project tek/düz klasör;
  .gitmodules yok, gitlink(160000) yok, iç içe .git yok. Platform git deposu
  boştu → `git add laravel_project/` ile 2501 dosya tracked edildi
  (vendor/node_modules/.env hariç). Commit atıldı (push YOK).
- [x] eager:true kontrol edildi/düzeltildi (A.3.1) — vardı; kaldırıldı,
  `resolvePageComponent` + `import.meta.glob` deseniyle sayfa-bazlı
  code-splitting aktif. app.js 1305 kB → 214 kB; LiveKit ayrı chunk
  (556 kB, sadece canlı sayfalarda). 35/35 test yeşil, build OK.
- [x] bootstrap-old.js/bootstrap.js kararı verildi ve uygulandı (A.3.2) —
  Kullanıcı kararı: **bootstrap-old.js silindi** (hiçbir yerden import
  edilmiyordu). `bootstrap.js` DURUYOR ama import EDİLMİYOR — içindeki
  `window.Echo` (Pusher/Echo gerçek-zamanlı) şu an bilinçli olarak devre dışı;
  broadcast=log. İleride gerçek-zamanlı özellik için ayrı bir turda aktive
  edilecek.
- [x] Ertelenen 4 CSS dosyası "kalıcı karar" olarak kapatıldı (A.3.3):
- [B] auth.css, auction-show.css, seller-live-card.css, balance-create/show.css
  → paylaşımlı class'lar nedeniyle KALICI OLARAK legacy.css içinde global
  bırakıldı (sayfaya özel scoped'a taşımak riskli/karmaşık, kazanç sınırlı
  çünkü zaten tek, minify+hash'li Vite paketi olarak yükleniyorlar). İleride
  tekrar değerlendirilebilir ama şu an kapalı madde.
- [x] PROGRESS.md sıfırlandı

## Bölüm B / Oturum 1 — Görsel Denetim (Faz 3)
- [x] Anasayfa denetlendi (masaüstü 1440)
- [x] İlan listesi (Browse/Auctions, Explore) denetlendi (masaüstü 1440)
- [x] İlan detay denetlendi (masaüstü 1440)
- [~] Mobil (390px): screenshot aracı viewport'u ~1568px'e zorladığı için gerçek
  390px render ALINAMADI. Mobil taşma/sıkışma görsel olarak doğrulanamadı →
  ilgili maddeler kod-seviyesi (Tailwind breakpoint) kontrolüyle ele alınacak
  veya kullanıcı onayıyla ertelenecek.
- [x] Rapor kullanıcıya iletildi, onay bekleniyor

### Bulgular (öncelikli)
| # | Sayfa | Bulgu | Öncelik |
|---|-------|-------|---------|
| 1 | Home vs Browse | **Kırık görsel tutarsızlığı**: Browse'da eksik görsel için "Görsel bulunamadı" placeholder var; Home'da aynı ilan sadece boş/karanlık alan olarak görünüyor (placeholder yok). Aynı `AuctionCard` iki sayfada farklı boş-durum gösteriyor. | Yüksek |
| 2 | Home (stories) | **Yükleme durumu cilası**: Hikaye barı yüklenirken avatarlar shimmer skeleton yerine dolu mavi/camgöbeği daireler olarak beliriyor ("yarım pasta" görünümü) — geçici ama kaba. | Orta |
| 3 | Tüm kart ızgaraları | **Kartlarda takılı odak/aktif halkası**: bazı kartlarda (ör. "El Yapımı Porselen", "Antika Masa") mavi bir kenarlık kalıyor gibi — focus-visible durumu fare etkileşiminden sonra da görünür kalabiliyor. | Düşük |
| 4 | İlan detay | **Yükleme sıçraması**: "KALAN" ve "İZLEYİCİ" değerleri önce "—" gösterip JS sonrası dolduruluyor; kısa görsel sıçrama. Ayrıca eksik görseller için küçük thumbnail'larda placeholder ikonu var (tutarlı). | Düşük |
| 5 | Explore | Kategori kutucukları (EL/AN/SA/MÜ) mor gradyan + baş harf — tutarlı. Öne Çıkanlar ızgarasında son satır yarım dolu (normal). Renk paleti korunacak (değişiklik yok). | Düşük (bilgi) |
| 6 | Genel | Kart hover geri bildirimi ve mikro-geçişler statik görüntüden doğrulanamadı; uygulama turunda ölçülü (0.15–0.3s) hover tutarlılığı gözden geçirilebilir. | Düşük |

> Önerilen uygulama gruplaması (Oturum 2+): **A)** #1 kırık-görsel placeholder
> tutarlılığı (AuctionCard) · **B)** #2 stories skeleton cilası · **C)** #3 focus
> ring + #6 hover tutarlılığı · **D)** #4 detay yükleme sıçraması. Her grup öncesi
> ayrı onay.


## Bölüm B / Oturum 2+ — Uygulama (tamamlandı, testing_agent it2+it3 PASS)
- [x] Kırık ilan görselleri düzeltildi: eksik `/storage/auctions/a1..a8.jpg` eklendi + AuctionCard opacity reveal garanti (`.idx-card-img img{opacity:1}`) → tüm kapaklar görünür, 0 adet 403.
- [x] StoryBar: avatar nötr taban zemin + mobil scroll-snap.
- [x] Mobil filtre kutusu kompaktlaştırıldı (/browse/auctions): 40px input, Kategori+Durum yan yana, sıralama chip'leri tek satır yatay scroll, Min/Max fiyat taşması giderildi (flex:1 1 0).
- [x] İkon FOUC + yumuşak açılış: bootstrap-icons/keenicons preload + `document.fonts.ready` (max 1200ms) beklenip `#app-loader` yumuşak gizleniyor → yenilemede ikonlar geç patlamıyor.
- [x] Public profil (/u/{username}) mobil: hizalı/tam genişlik (testing_agent doğruladı).
- [x] Regresyon: 35/35 test yeşil, desktop %100, mobil %100 (scrollWidth=390, 0 konsol hatası).

### Kalan LOW (kullanıcı şikayeti değil, ileride)
- [ ] Header genel arama input'u mobilde ~140px (iteration_1'den beri) — ayrı tur.
- [ ] `.brz-count` "16 sonuç" chip scroll şeridi sonunda — kozmetik.

## Kapsam Dışı (bu tur için)
- [B] Canlı yayın ekranları (Browse/Live listesi + canlı yayın izleme sayfası) — kullanıcı isteğiyle bu turun kapsamı dışında bırakıldı
- [B] Admin/Seller panelleri — ayrı bir tur
- [B] Auth sayfaları (login/register) — ayrı bir tur
