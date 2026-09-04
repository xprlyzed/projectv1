# ═══════════════════════════════════════════════════════════════════
# SABİT KURAL — PUSH HEDEFİ
# ═══════════════════════════════════════════════════════════════════
# PUSH HEDEFİ SADECE VE HER ZAMAN: https://github.com/xprlyzed/projectv1
# — YENİ REPO OLUŞTURULMAYACAK, BAŞKA REPO'YA (projectv2, projectv9, projectv10 dahil) PUSH EDİLMEYECEK.
# ═══════════════════════════════════════════════════════════════════


# ═══════════════════════════════════════════════════════════════════
# SABİT KURAL — REPO YAPISI KONTROLÜ (HER GÖREVDEN ÖNCE + HER PUSH ÖNCESİ)
# ═══════════════════════════════════════════════════════════════════
# Amaç: Proje yapısı bir daha ASLA bozulmasın (nested .git / submodule / laravel_project sarmalayıcı klasör).
#
# HER YENİ GÖREVE BAŞLAMADAN ve HER PUSH'TAN HEMEN ÖNCE aşağıdaki kontrol listesini çalıştır:
#   1) find . -maxdepth 3 -name ".git" -type d       → SADECE  ./.git  çıkmalı (kökte tek .git).
#   2) git ls-files -s | grep "^160000"               → BOŞ olmalı (submodule referansı yok).
#   3) cat .gitmodules                                → Dosya OLMAMALI (vendor/node_modules hariç).
#   4) Kök dizinde app/ routes/ public/ composer.json artisan DOĞRUDAN durmalı (laravel_project/auction-project sarmalayıcısı YOK).
#   5) Yeni bir klasörü clone/kopyalayarak eklediysen: o klasörün kendi .git'ini MUTLAKA sil (rm -rf <klasor>/.git).
#   6) Push öncesi git status'ta dosyalar TEK TEK listelenmeli (tek satır "new file: <klasor>" submodule referansı DEĞİL).
#
# Bu kural bozulmadıkça, her doğrulamadan sonra buraya tarih + "temiz" notu düş (aşağıya ekle).
#
# DOĞRULAMA GEÇMİŞİ:
#   - 2026-09-03: Repo tarandı → tek ./.git, submodule yok, .gitmodules yok, kök DÜZ (app/, routes/, composer.json kökte).
#                 GitHub (xprlyzed/projectv10) kökü de DÜZ teyit edildi. Durum: TEMİZ.
# ═══════════════════════════════════════════════════════════════════


# ═══════════════════════════════════════════════════════════════════
# BÖLÜM 2 — CANLI YAYIN DENEYİMİ (TikTok/Kick seviyesi) — GÖREV LİSTESİ
# ═══════════════════════════════════════════════════════════════════
# TEŞHİS KÖK NEDEN (2026-09-03): LiveKit yayınının yanında ESKİ bir stream kontrolü
# (auction-show.js: WebRTC handleOffer + _showLiveStream/_hideLiveStream + pollLiveState'in
# is_live'a göre video temizlemesi) AYNI #liveVideo elementini yönetiyor. pollLiveState her 2.5sn
# `!is_live` görünce _hideLiveStream() → video.srcObject=null + "yayın başlatılmadı" banner.
# → Freeze + yanlış mesajın ana kaynağı: legacy ile LiveKit çakışması. Çözüm: LiveKit tek kaynak.
#
# [x] G1 [KRİTİK] "Yayın başlatılmadı" yanlış mesajı → 3-durumlu (checking/live/offline) nötr spinner;
#          is_live + grace mantığı; legacy'nin video/cam-off kontrolü no-op'landı.
#          KANIT: testing_agent iteration_1 → t0-3.5sn stream-checking=true & stream-offline=false; 8sn grace sonrası offline (beklenen).
# [~] G2 [KRİTİK] Freeze → legacy WebRTC/video kontrolü DEVRE DIŞI (auction-show.js handleOffer/_show/_hideLiveStream no-op);
#          publisher encoding/simulcast/degradation tuning (Broadcast.vue publishDefaults). KOD TAMAM + build'de.
#          NOT: Gerçek kamera yayınıyla throttling altında freeze testi headless'te SİMÜLE EDİLEMEZ → gerçek yayıncı ile doğrulanacak.
# [x] G3 [KRİTİK] Mobil tam-ekran dikey video + birleşik (mesaj+teklif) kayan feed +
#          alt sabit input (Sohbet/Teklif toggle + onay) + üst overlay + otomatik bağlan (MobileLiveRoom.vue).
#          + Marka renkleri (#155EEF mavi / #10b981 yeşil), kapat→FAB→tekrar aç, mobilde eski satır-içi sohbet/teklif GİZLİ, masaüstü etkilenmedi.
#          KANIT: testing_agent iteration_2 → 6/6 kriter PASS (chat gönder, teklif onay 31.200₺, close→FAB→reopen, desktop non-regression, marka rengi).
# [ ] G4 [YÜKSEK] Masaüstü canlı deneyimini (video + yan panel) rahatlat (mevcut üzerine).
# [ ] G5 [ORTA] Bağlantı kalite göstergesi (ConnectionQuality).
# [ ] G6 [ORTA] Yayıncı tek-tık başlat / izleyici otomatik bağlan sadeleştirme.
# ═══════════════════════════════════════════════════════════════════


# artirdim.com — Realtime & UI İyileştirme Süreç Takibi (process.md)

> Durum: [ ] yapılmadı · [~] devam · [x] tamam (KANITLI) · [B] bloke/ertelendi
> Karar: Realtime taşıyıcı = **LiveKit veri kanalı** (senkron `LiveKitPublisher`, queue gerekmez).
>        DM mesajları şu an polling; anlıklaştırılacak.
> KURAL: Bir madde ancak testing_agent (veya iki-kullanıcı gerçek test) KANITIYLA [x] olur.
>        Kanıt = değişen dosyalar + build/cache adımı + test sonucu.

---

## MİMARİ NOTLARI (ADIM 0 taramasında doğrulandı — 2026-09)
- Çift asset pipeline: `app.blade.php` → (a) statik `public/assets/**` (build GEREKMEZ: `auction-show.js`,
  `style.bundle.css`, `scripts.bundle.js`) + (b) `@vite(legacy.css, app.js)` (build GEREKİR).
  `legacy.css` → `theme-new.css`, `auction-show.css` vb. @import ediyor.
  → UI değişikliğinde: doğru pipeline'ı düzenle, gerekiyorsa `yarn build` + `php artisan view:clear config:clear`.
- İzleyici realtime: `public/assets/js/custom/auction-show.js` içinde `window.__onRemoteBid`/`__onRemoteChat`
  tanımlı; LiveKit `onData` → bunlar. Yedek: `pollLiveState` 2.5sn, `pollChat` 3sn.
- Broadcast=log + queue worker YOK → `broadcast(new BidPlaced)` no-op; gerçek taşıyıcı LiveKit.
- LiveKit: `config/services.php` → env. Bağlantı testi BAŞARILI. `.env` gitignore'lu, commit/log edilmedi.
- Repo: submodule/iç içe YOK; geçici `projectv8` gitlink temizlendi → yapı düz.

---

## KRİTİK

- [x] 1. Teklif anlıklığı — o ilanı görüntüleyen HERKESE (satıcı + tüm izleyiciler) sayfa yenilemeden anlık:
      güncel en yüksek teklif + teklif sayısı + teklif geçmişi. **KANITLI (testing_agent iteration_8, 2026-09):**
      2 ayrı oturum (buyer+admin), sayfa yenilemeden #live-price 5.568→99.999→150.000 ₺, #live-bid-count 7→9,
      feed dedup doğru, gecikme 0.46–0.47sn, JS/PHP hatası yok. Dosyalar zaten mevcuttu (kod değişmedi).
- [x] 2. Mesajlaşma anlıklığı — DM'ler artık LiveKit veri kanalıyla `dm-{conversationId}` odasına anlık yayınlanıyor;
      polling (2500ms) yalnızca yedek. **KANITLI (testing_agent iteration_9, 2026-09):** çift yönlü iletim
      0.26s/0.79s (<1sn), dedup doğru, 4 ardışık mesajda sıra korundu, /livekit/dm-token 200, hata yok.
      Dosyalar: LiveKitPublisher::publishToRoom, LiveKitDmTokenController (+route), MessageController@store,
      Messages/Index.vue (connectDm+watch), useLiveKit.js (fetchToken/tokenUrl).
- [x] 3. Sekme arka plan→ön / route değişimi / ağ kesintisi→dönüş → LiveKit otomatik yeniden bağlanıyor.
      **KANITLI (testing_agent iteration_10, 2026-09):** route değişimi 0.43s, offline→online 0.43s,
      sekme görünürlük DM 0.25s; hepsinde manuel reload YOK, dedup doğru, kalıcı hata yok.
      Dosya: useLiveKit.js connectRoom reconnect katmanı (Disconnected + visibilitychange + online/focus).
- [x] 4. Satıcının 10sn sayacı çalışırken mobilde alıcılar teklif vermeye DEVAM edebiliyor.
      **KANITLI (testing_agent iteration_11, 2026-09):** izleyici sayacı tam-ekran overlay yerine kompakt üst
      yeşil banner (44px, pointer-events:none); mobil teklif çubuğu görünür+tıklanabilir (bid-urgent vurgu),
      alıcı sayaç sırasında 350.000 ₺ teklif verebildi, elementFromPoint submit'i en üstte doğruladı.
      Dosyalar: Show.vue __showCountdown/__removeCd, theme-new.css (.lk-sale-banner, .bid-urgent).

## YÜKSEK

- [x] 5. LiveKit uçtan uca: **KANITLI (testing_agent iteration_12, 2026-09):** sahte kamerayla satıcı yayın
      açtı (1280x720, errorMsg yok), izleyici #liveVideo'da uzak track aldı (640x360, oynatılıyor),
      toggleCam detach/re-subscribe çalıştı. Bağlantı/token/veri kanalı zaten #1-#4'te kanıtlıydı.
- [x] 6. Satıcı canlı yayın ekranı yeniden tasarlandı: üst "Canlı Özet" şeridi (Güncel Teklif, Son Teklifi Veren,
      Teklif Sayısı, Kalan Süre) yeni teklifte anlık güncellenir; ferah düzen, mobilde 2 sütun.
      **KANITLI (testing_agent it13 A1/A2/A3 + it14 B1 PASS).** Ayrıca alıcı sayacı artık medya alanı ÜZERİNDE
      (masaüstünde header'da değil, y≈220) — kullanıcı şikayeti giderildi.
      Dosyalar: Seller/Broadcast.vue (hero+style), BroadcastController@show (current_price+ends_at_ts),
      Show.vue __showCountdown (medya alanına anchor), theme-new.css (.lk-sale-banner--onvideo).
- [ ] 7. Alıcı mobil ekranları (canlı yayın + teklif verme): büyük dokunma hedefleri, "Teklif Ver" sabit/erişilebilir,
      karmaşa yok. Yansıdığı KANITLANACAK.

## TASARIM YÖNÜ (tüm yeniden düzenlemelerde)
- Mevcut renk paleti/marka dili korunur (mavi accent, açık arkaplan, rounded-xl kartlar).
- Ferah, şık, nefes alan düzen; sıkışık/iç içe bileşenlerden kaçın.
- Kullanıcı hiçbir noktada butona ulaşamama/engellenme yaşamamalı.
- Hem masaüstü hem mobil ayrı ayrı test edilir.

---

## ÇALIŞMA GÜNLÜĞÜ (kanıtlı kayıtlar buraya)

### ADIM 0 — Mevcut durum taraması (2026-09) [x]
- Repo yapısı, process.md `[x]` maddeleri, realtime/messaging/countdown/LiveKit/UI-pipeline kod üzerinden doğrulandı.
- Bulgular yukarıdaki "MİMARİ NOTLARI" + görev listesine işlendi. `projectv8` gitlink temizlendi.
- LiveKit anahtarları `.env`'e eklendi (maskeli), bağlantı testi BAŞARILI.

### (Önceki oturumdan taşınan iddialar — kanıt yeniden alınana kadar [ ])
- Görev #1: "iteration_6 PASS" iddiası vardı; işaret çelişkili olduğu için sıfırlandı, yeniden doğrulanacak.
- Görev #2: backend LiveKit chat + DM polling 1500ms iddiası; DM hâlâ gecikmeli → yarım kabul edildi.


---

## OTURUM 2026-09 (B) — ADIM 0 yeniden tarama + repo + yeni revizyonlar

### ADIM 0 bulguları (KOD ile doğrulandı, işaretlere güvenilmedi)
- **Premise düzeltmesi:** "Alıcı tarafı yapılmadı" iddiası YANLIŞ. Alıcı canlı izleme sayfası VAR:
  `resources/js/Pages/Auctions/Show.vue` + `public/assets/js/custom/auction-show.js`.
  Satıcı ile AYNI realtime altyapısı: `useLiveKit.connectRoom` + `auction-{id}` LiveKit odası.
  Teklif anlık (`__onRemoteBid`), sohbet (`__onRemoteChat`), satış sayacı (medya-üstü non-blocking),
  viewer LiveKit izleme, mobil sticky teklif çubuğu — hepsi alıcıda mevcut ve çalışıyor.
- **Satıcı realtime (#1-6):** kod düzeyinde mevcut. Zayıf nokta: broadcaster yayın odası (`goLive` ham `new Room()`)
  kendi reconnect sarmalayıcısını kullanmıyor (izleyici/data odalarında var).
- **Pin (mesaj sabitleme): HİÇBİR yerde yok** — `auction_chat_messages`: id, auction_id, user_id, message, is_seller, ts. → tamamen yeni.
- **Satıcı `Broadcast.vue`:** `.bc-root{max-width:1400px}` (dar), kontroller video ALTINDA düz flex sıra (floating değil).
- **LiveKit** sunucu bağlantı testi: BAŞARILI (anahtarlar loglanmadı, `.env` gitignore'lu).

### Repo temizliği (2026-09-B) [x]
- Yorum 2 uygulandı: kökten `backend/ frontend/ tests/ test_reports/ memory/` + 5 kopya .md
  (CANLI_YAYIN/INERTIA/KURULUM/PROGRESS/test_result) silindi. Kök = `laravel_project/` + git + README.
  Submodule/iç içe yok; `laravel_project` kendi .git'i yok. Silmeler yeni commit'e yansır (geçmiş korunur).
- app-loader: kullanıcı "sağlıklı çalışıyor" dedi → bring-up geçici değişiklikleri geri alındı, orijinal korunur.

## YENİ REVİZYONLAR (öncelik sırası: a)

### SATICI CANLI YAYIN SAYFASI (Broadcast.vue)
- [x] R1 [KRİTİK] Genişlik: `.bc-root` 1400px sınırı kaldırıldı → full-width. AppLayout'a sayfa-bazlı
      akışkan kap eklendi (fluidPages=['Seller/Broadcast','Auctions/Show'] → container-fluid).
      **KANITLI (testing_agent it1):** #kt_app_content_container 1920 viewport'ta 1600px (container-xxl ~1320'ye karşı),
      sidebar sağında neredeyse tüm alanı kullanıyor. Masaüstü+mobil geçti, hata yok.
- [x] R2 [YÜKSEK] Floating kontrol çubuğu: kontroller `.bc-fab` ile video ÜZERİNE taşındı (yarı saydam, blur,
      ortalanmış, ikon+etiket, hover/active geri bildirimli; canlı modda kompakt ikon-only).
      **KANITLI (testing_agent it1):** [data-testid=broadcast-controls] position:absolute, parent .bc-video-wrap,
      bbox video kutusu içinde; ön-yayın butonları (preview/go-live/link) görünür+tıklanabilir; mobilde erişilebilir.
      Mobil kozmetik (ipucu örtme + hero kırpma) düzeltildi.
- [ ] R3 [YÜKSEK] Mesaj pin: `auction_chat_messages` + `is_pinned, pinned_at`; pin/unpin endpoint (yalnız satıcı);
      LiveKit `pin` event; satıcı+alıcı UI'da en üstte sabit "📌 Sabitlenmiş" mesaj; realtime yayılır.
- [ ] R4 [YÜKSEK] İyileştirmeler (hepsi onaylandı): video-üstü yeni-teklif toast; CANLI rozeti + bağlantı kalitesi göstergesi;
      sohbet moderasyonu (kullanıcı susturma + mesaj silme); mobilde sohbet collapse/expand.

### ALICI CANLI İZLEME SAYFASI (Auctions/Show.vue)
- [x] R5 [KRİTİK] Alıcı izleme sayfası satıcıyla tutarlı + full-width'e alındı; MEVCUT sayfa revize edildi.
      Video 16/9 & yükseklik-kapalı (max 72vh) & ortalı (satıcıyla tutarlı). **KANITLI (testing_agent it2):**
      teklif→anlık fiyat güncelleme reload'suz (6.324→6.426→6.528), bid feed anlık. Ayrıca cam-off bannerı hatası
      düzeltildi: video UI yalnızca gerçek video TrackSubscribed'da açılır (yayın yokken banner görünür, sahte CANLI yok)
      **KANITLI (testing_agent it3, masaüstü+mobil).**  NOT: "pin gösterimi" kısmı R3'e bağlı (pin henüz yok) → R3'te tamamlanacak.
- [x] R6 [YÜKSEK] Alıcı UI/UX: full-width geniş video; sağ kolon teklif paneli masaüstünde STICKY (Teklif Ver hep görünür);
      mobil alt sabit teklif çubuğu (chip'ler 40px dokunma hedefi), input + "Teklif Ver" erişilebilir, yatay taşma yok.
      **KANITLI (testing_agent it2, masaüstü 1920 + mobil 390).**  Sohbet + sabit mesaj gösterimi R3 (pin) ile gelecek.

> Test kuralı: her madde testing_agent (2 kullanıcı, gerçek LiveKit) kanıtıyla [x]. Kanıt yoksa [x] YOK.
