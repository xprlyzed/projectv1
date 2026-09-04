<script setup>
/*
 * MobileLiveRoom — TikTok/Kick tarzı mobil tam-ekran canlı yayın deneyimi.
 * - Dikey tam ekran video (LiveKit viewer, otomatik bağlan, muted autoplay + tek dokunuşla ses)
 * - Birleşik kayan feed: sohbet mesajları + gelen teklifler tek listede (teklif satırı vurgulu)
 * - Alt sabit yarı saydam input: "Sohbet / Teklif" toggle; teklifte tek-dokunuş onay
 * - Üst overlay: güncel en yüksek teklif + kalan süre + izleyici + CANLI
 * Legacy auction-show.js mobilde bu deneyimi yönetmez; bileşen kendi LiveKit odasını kurar.
 */
import { ref, computed, onMounted, onBeforeUnmount, nextTick, watch } from 'vue';
import { connectRoom } from '@/composables/useLiveKit';
import { RoomEvent, Track } from 'livekit-client';

const props = defineProps({ a: Object, config: Object });
const emit = defineEmits(['close']);

const videoEl = ref(null);
const feedBox = ref(null);
let room = null;
let graceTimer = null;

const connState = ref((props.a?.is_live && !props.a?.has_finished) ? 'checking' : 'offline'); // checking|live|offline
const muted = ref(true);
const viewers = ref(0);
const feed = ref([]);
let feedSeq = 0;

const step = Number(props.config?.min_increment) || 0;
const minBid = ref(Number(props.a?.min_bid) || 0);
const topPrice = ref(props.a?.display_price || '—');
const bidCount = ref(Number(props.a?.bid_count) || 0);

const mode = ref('chat');        // 'chat' | 'bid'
const draft = ref('');           // sohbet metni
const bidDraft = ref('');        // teklif tutarı
const sending = ref(false);
const pendingBid = ref(null);    // onay bekleyen teklif tutarı
const errorMsg = ref('');

const remaining = ref(Number(props.config?.remaining_secs) || 0);
let clockTimer = null;
let chatTimer = null;
let chatLastId = 0;
let bidLastId = Number(props.config?.last_bid_id) || 0;

const isAuth = computed(() => props.config?.is_auth === '1');
const csrf = () => props.config?.csrf || document.querySelector('meta[name="csrf-token"]')?.content || '';
const fmtTL = (v) => new Intl.NumberFormat('tr-TR').format(Math.round(Number(v) || 0)) + ' ₺';

const quickBids = computed(() => {
    const base = minBid.value || 0;
    return [
        { amount: base, label: fmtTL(base) },
        { amount: base + step, label: fmtTL(base + step) },
        { amount: base + step * 5, label: fmtTL(base + step * 5) },
    ];
});

const remainingText = computed(() => {
    let s = remaining.value;
    if (s <= 0) return 'Bitti';
    const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
    if (d > 0) return `${d}g ${h}s`;
    if (h > 0) return `${h}s ${m}dk`;
    if (m > 0) return `${m}dk ${sec}sn`;
    return `${sec}sn`;
});

const seenChatIds = new Set();
const seenBidIds = new Set();
function pushFeed(item) {
    // id bazlı dedupe: optimistic ekleme + poll/broadcast yarışında aynı kayıt iki kez eklenmesin.
    if (item.kind === 'chat' && item.id != null) {
        if (seenChatIds.has(item.id)) return;
        seenChatIds.add(item.id);
    } else if (item.kind === 'bid' && item.bidId != null) {
        if (seenBidIds.has(item.bidId)) return;
        seenBidIds.add(item.bidId);
    }
    feed.value.push({ _k: ++feedSeq, ...item });
    if (feed.value.length > 60) feed.value.splice(0, feed.value.length - 60);
    nextTick(() => {
        const el = feedBox.value;
        if (el) el.scrollTop = el.scrollHeight;
    });
}

function onData(msg) {
    if (!msg || !msg.type) return;
    if (msg.type === 'new-bid') {
        if (msg.bid_id && msg.bid_id <= bidLastId) return;
        if (msg.bid_id) bidLastId = msg.bid_id;
        if (msg.display_price) topPrice.value = msg.display_price;
        if (typeof msg.total_bids !== 'undefined') bidCount.value = msg.total_bids;
        if (msg.amount) minBid.value = Number(msg.amount) + step;
        pushFeed({ kind: 'bid', bidId: msg.bid_id, name: msg.bidder_name || msg.name || 'Bir alıcı', amount: fmtTL(msg.amount) });
    } else if (msg.type === 'chat') {
        if (msg.id && msg.id <= chatLastId) return;
        if (msg.id) chatLastId = msg.id;
        pushFeed({ kind: 'chat', id: msg.id, name: msg.user_name || 'Kullanıcı', text: msg.message || '', seller: !!msg.is_seller });
    }
}

function hasVideo() {
    if (!room) return false;
    let found = false;
    room.remoteParticipants.forEach((p) => p.trackPublications.forEach((pub) => {
        if (pub.isSubscribed && pub.track && pub.track.kind === Track.Kind.Video) found = true;
    }));
    return found;
}

async function connect() {
    if (!props.a?.slug) return;
    try {
        room = await connectRoom({
            auctionSlug: props.a.slug,
            role: 'viewer',
            csrf: csrf(),
            videoEl: videoEl.value,
            onData,
            onParticipants: (n) => { viewers.value = Math.max(0, (n || 1) - 1); },
        });
        room.on(RoomEvent.TrackSubscribed, (track) => {
            if (track.kind === Track.Kind.Video) { if (graceTimer) { clearTimeout(graceTimer); graceTimer = null; } connState.value = 'live'; }
        });
        room.on(RoomEvent.TrackUnsubscribed, (track) => { if (track.kind === Track.Kind.Video && !hasVideo()) connState.value = 'offline'; });
        viewers.value = Math.max(0, (room.numParticipants || 1) - 1);
        if (hasVideo()) {
            connState.value = 'live';
        } else if (props.a?.is_live && !props.a?.has_finished) {
            connState.value = 'checking';
            graceTimer = setTimeout(() => { if (connState.value !== 'live') connState.value = 'offline'; }, 8000);
        } else {
            connState.value = 'offline';
        }
    } catch (e) {
        connState.value = 'offline';
    }
}

function toggleMute() {
    muted.value = !muted.value;
    if (videoEl.value) videoEl.value.muted = muted.value;
}

async function loadChatHistory() {
    if (!props.config?.chat_poll_url) return;
    try {
        const res = await fetch(props.config.chat_poll_url + '?after=' + chatLastId, {
            headers: { Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
        });
        if (!res.ok) return;
        const d = await res.json();
        (d.messages || []).forEach((m) => {
            if (m.id > chatLastId) { chatLastId = m.id; pushFeed({ kind: 'chat', id: m.id, name: m.user_name, text: m.message, seller: !!m.is_seller }); }
        });
    } catch (e) { /* sessiz */ }
}

async function sendChat() {
    const text = (draft.value || '').trim();
    if (!text || sending.value) return;
    errorMsg.value = '';
    sending.value = true;
    try {
        const res = await fetch(props.config.chat_store_url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf(), Accept: 'application/json' },
            body: JSON.stringify({ message: text }),
        });
        const d = await res.json().catch(() => ({}));
        if (res.ok) {
            draft.value = '';
            if (d.id && d.id > chatLastId) { chatLastId = d.id; }
            pushFeed({ kind: 'chat', id: d.id, name: d.user_name || 'Sen', text: d.message || text, seller: !!d.is_seller, mine: true });
        } else {
            errorMsg.value = d.message || 'Mesaj gönderilemedi.';
        }
    } catch (e) { errorMsg.value = 'Bağlantı hatası.'; }
    sending.value = false;
}

function askBid() {
    errorMsg.value = '';
    const amount = parseFloat(bidDraft.value);
    if (!amount || amount < minBid.value) {
        errorMsg.value = `En az ${fmtTL(minBid.value)} girmelisiniz.`;
        return;
    }
    pendingBid.value = amount;
}

function quickPick(amount) {
    bidDraft.value = amount;
    errorMsg.value = '';
    pendingBid.value = amount;
}

async function confirmBidNow() {
    const amount = pendingBid.value;
    if (!amount || sending.value) return;
    sending.value = true;
    errorMsg.value = '';
    try {
        const res = await fetch(props.config.bid_url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf(), Accept: 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
            body: JSON.stringify({ amount }),
        });
        const d = await res.json().catch(() => ({}));
        if (res.ok) {
            bidDraft.value = '';
            pendingBid.value = null;
            if (d.bid_id && d.bid_id > bidLastId) bidLastId = d.bid_id;
            if (d.display_price) topPrice.value = d.display_price;
            if (typeof d.total_bids !== 'undefined') bidCount.value = d.total_bids;
            minBid.value = Number(d.amount) + step;
            pushFeed({ kind: 'bid', bidId: d.bid_id, name: (d.bidder_name || 'Sen'), amount: fmtTL(d.amount), mine: true });
        } else {
            errorMsg.value = d.message || 'Teklif verilemedi.';
        }
    } catch (e) { errorMsg.value = 'Bağlantı hatası.'; }
    sending.value = false;
}

function cancelBid() { pendingBid.value = null; }

function onSubmit() {
    if (!isAuth.value) { window.location.href = props.config.login_url; return; }
    if (mode.value === 'chat') sendChat();
    else askBid();
}

onMounted(async () => {
    // Sayfa arka planı kaymasın
    document.body.style.overflow = 'hidden';
    if (videoEl.value) videoEl.value.muted = true;
    // İlk teklifleri feed'e koy (varsa) — en yeni altta
    if (Array.isArray(props.a?.bids)) {
        [...props.a.bids].reverse().forEach((b) => pushFeed({ kind: 'bid', name: b.name, amount: b.amount_fmt, seed: true }));
    }
    await loadChatHistory();
    connect();
    clockTimer = setInterval(() => { if (remaining.value > 0) remaining.value--; }, 1000);
    chatTimer = setInterval(loadChatHistory, 4000);
});

onBeforeUnmount(() => {
    document.body.style.overflow = '';
    if (graceTimer) clearTimeout(graceTimer);
    if (clockTimer) clearInterval(clockTimer);
    if (chatTimer) clearInterval(chatTimer);
    if (room) { try { room.disconnect(); } catch (e) {} room = null; }
});

function close() { emit('close'); }
</script>

<template>
    <div class="mlr" data-testid="mobile-live-room">
        <!-- VİDEO (tam ekran) -->
        <video ref="videoEl" class="mlr-video" autoplay playsinline muted @click="toggleMute" data-testid="mlr-video"></video>

        <!-- Bağlanıyor / kapalı durum katmanı -->
        <div v-if="connState === 'checking'" class="mlr-state" data-testid="mlr-checking">
            <div class="mlr-spin"></div>
            <p>Yayına bağlanılıyor…</p>
        </div>
        <div v-else-if="connState === 'offline'" class="mlr-state" data-testid="mlr-offline">
            <i class="bi bi-camera-video-off"></i>
            <p>Satıcı henüz yayın başlatmadı</p>
        </div>

        <!-- ÜST OVERLAY -->
        <div class="mlr-top">
            <div class="mlr-top-left">
                <img class="mlr-ava" :src="a.seller?.profile_img" :alt="a.seller?.name">
                <div class="mlr-seller">
                    <div class="mlr-seller-name">{{ a.seller?.name }}</div>
                    <div class="mlr-viewers"><i class="bi bi-people-fill"></i> {{ viewers }}</div>
                </div>
                <span v-if="connState === 'live'" class="mlr-live" data-testid="mlr-live-pill"><span class="dot"></span> CANLI</span>
            </div>
            <div class="mlr-top-right">
                <button class="mlr-icon" @click="toggleMute" :title="muted ? 'Sesi aç' : 'Sesi kapat'" data-testid="mlr-mute">
                    <i class="bi" :class="muted ? 'bi-volume-mute' : 'bi-volume-up'"></i>
                </button>
                <button class="mlr-icon" @click="close" title="Kapat" data-testid="mlr-close">
                    <i class="bi bi-x-lg"></i>
                </button>
            </div>
        </div>

        <!-- FİYAT / SÜRE ŞERİDİ -->
        <div class="mlr-price">
            <div class="mlr-price-item">
                <span class="lbl">Güncel</span>
                <span class="val" data-testid="mlr-top-price">{{ topPrice }}</span>
            </div>
            <div class="mlr-price-item">
                <span class="lbl"><i class="bi bi-clock"></i></span>
                <span class="val" :class="{ crit: remaining > 0 && remaining <= 60 }" data-testid="mlr-remaining">{{ remainingText }}</span>
            </div>
            <div class="mlr-price-item">
                <span class="lbl">Teklif</span>
                <span class="val">{{ bidCount }}</span>
            </div>
        </div>

        <!-- BİRLEŞİK FEED (mesaj + teklif) -->
        <div ref="feedBox" class="mlr-feed" data-testid="mlr-feed">
            <div v-for="it in feed" :key="it._k"
                 class="mlr-row" :class="it.kind === 'bid' ? 'is-bid' : 'is-chat'"
                 :data-testid="it.kind === 'bid' ? 'mlr-feed-bid' : 'mlr-feed-chat'">
                <template v-if="it.kind === 'bid'">
                    <i class="bi bi-hammer"></i>
                    <span class="who">{{ it.name }}</span>
                    <span class="act">teklif verdi</span>
                    <span class="amt">{{ it.amount }}</span>
                </template>
                <template v-else>
                    <span class="who" :class="{ seller: it.seller }">{{ it.name }}<span v-if="it.seller" class="badge-seller">SATICI</span></span>
                    <span class="txt">{{ it.text }}</span>
                </template>
            </div>
        </div>

        <!-- ALT INPUT -->
        <div class="mlr-bottom">
            <template v-if="isAuth && a.is_active && !a.is_owner">
                <!-- Onay çubuğu -->
                <div v-if="pendingBid" class="mlr-confirm" data-testid="mlr-bid-confirm">
                    <span><b>{{ fmtTL(pendingBid) }}</b> teklif verilsin mi?</span>
                    <div class="mlr-confirm-btns">
                        <button class="mlr-btn ghost" @click="cancelBid" data-testid="mlr-bid-cancel">Vazgeç</button>
                        <button class="mlr-btn go" :disabled="sending" @click="confirmBidNow" data-testid="mlr-bid-confirm-yes">
                            <i class="bi bi-lightning-charge-fill"></i> Onayla
                        </button>
                    </div>
                </div>

                <!-- Teklif hızlı çipleri -->
                <div v-if="mode === 'bid' && !pendingBid" class="mlr-chips" data-testid="mlr-quick-chips">
                    <button v-for="(q, i) in quickBids" :key="i" class="mlr-chip" @click="quickPick(q.amount)" :data-testid="`mlr-quick-${i}`">{{ q.label }}</button>
                </div>

                <div v-if="errorMsg" class="mlr-err" data-testid="mlr-error">{{ errorMsg }}</div>

                <div v-if="!pendingBid" class="mlr-input-row">
                    <div class="mlr-toggle" data-testid="mlr-mode-toggle">
                        <button :class="{ on: mode === 'chat' }" @click="mode = 'chat'; errorMsg=''" data-testid="mlr-mode-chat">Sohbet</button>
                        <button :class="{ on: mode === 'bid' }" @click="mode = 'bid'; errorMsg=''" data-testid="mlr-mode-bid">Teklif</button>
                    </div>
                    <input v-if="mode === 'chat'" v-model="draft" class="mlr-input" type="text" maxlength="300"
                           placeholder="Mesaj yaz…" @keyup.enter="onSubmit" data-testid="mlr-chat-input">
                    <input v-else v-model="bidDraft" class="mlr-input" type="number" :min="minBid" :step="step"
                           :placeholder="`En az ${fmtTL(minBid)}`" @keyup.enter="onSubmit" data-testid="mlr-bid-input">
                    <button class="mlr-send" @click="onSubmit" :disabled="sending" data-testid="mlr-send">
                        <i class="bi" :class="mode === 'bid' ? 'bi-lightning-charge-fill' : 'bi-send-fill'"></i>
                    </button>
                </div>
            </template>
            <template v-else-if="a.is_owner">
                <div class="mlr-note">Bu sizin ilanınız — yayın yönetimi için satıcı panelini kullanın.</div>
            </template>
            <template v-else-if="!isAuth">
                <a :href="config.login_url" class="mlr-login" data-testid="mlr-login">Sohbet ve teklif için giriş yap</a>
            </template>
            <template v-else>
                <div class="mlr-note">Bu müzayede için teklif kapalı.</div>
            </template>
        </div>
    </div>
</template>

<style scoped>
.mlr { position: fixed; inset: 0; z-index: 4000; background: #000; overflow: hidden; display: flex; flex-direction: column; }
.mlr-video { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; background: #000; }

.mlr-state { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 12px; color: rgba(255,255,255,.6); z-index: 2; }
.mlr-state i { font-size: 54px; color: rgba(255,255,255,.18); }
.mlr-state p { font-size: 14px; margin: 0; }
.mlr-spin { width: 46px; height: 46px; border-radius: 50%; border: 4px solid rgba(255,255,255,.15); border-top-color: #155eef; animation: mlr-rot .8s linear infinite; }
@keyframes mlr-rot { to { transform: rotate(360deg); } }

.mlr-top { position: absolute; top: 0; left: 0; right: 0; z-index: 6; display: flex; align-items: flex-start; justify-content: space-between; padding: calc(env(safe-area-inset-top, 0px) + 12px) 12px 28px; background: linear-gradient(to bottom, rgba(0,0,0,.65), transparent); }
.mlr-top-left { display: flex; align-items: center; gap: 8px; }
.mlr-ava { width: 38px; height: 38px; border-radius: 50%; object-fit: cover; border: 2px solid rgba(255,255,255,.85); }
.mlr-seller-name { color: #fff; font-weight: 700; font-size: 14px; text-shadow: 0 1px 3px rgba(0,0,0,.6); }
.mlr-viewers { color: rgba(255,255,255,.85); font-size: 12px; display: flex; align-items: center; gap: 4px; }
.mlr-live { display: inline-flex; align-items: center; gap: 5px; background: #10b981; color: #04120c; font-size: 10px; font-weight: 800; padding: 3px 8px; border-radius: 20px; letter-spacing: .4px; }
.mlr-live .dot { width: 6px; height: 6px; border-radius: 50%; background: #04120c; animation: mlr-blink 1s infinite; }
@keyframes mlr-blink { 50% { opacity: .3; } }
.mlr-top-right { display: flex; gap: 8px; }
.mlr-icon { width: 38px; height: 38px; border-radius: 50%; border: none; background: rgba(0,0,0,.35); backdrop-filter: blur(8px); color: #fff; font-size: 16px; display: flex; align-items: center; justify-content: center; cursor: pointer; }

.mlr-price { position: absolute; top: calc(env(safe-area-inset-top, 0px) + 60px); left: 12px; right: 12px; z-index: 6; display: flex; justify-content: space-between; gap: 8px; }
.mlr-price-item { display: flex; flex-direction: column; background: rgba(0,0,0,.4); backdrop-filter: blur(8px); border-radius: 10px; padding: 5px 10px; }
.mlr-price-item .lbl { font-size: 11px; color: rgba(255,255,255,.65); text-transform: uppercase; letter-spacing: .3px; }
.mlr-price-item .val { font-size: 16px; font-weight: 800; color: #fff; }
.mlr-price-item .val.crit { color: #f87171; }

.mlr-feed { position: absolute; left: 0; right: 78px; bottom: 96px; z-index: 5; max-height: 42vh; overflow-y: auto; padding: 0 12px; display: flex; flex-direction: column; gap: 6px; scrollbar-width: none; -webkit-mask-image: linear-gradient(to top, #000 78%, transparent); mask-image: linear-gradient(to top, #000 78%, transparent); }
.mlr-feed::-webkit-scrollbar { display: none; }
.mlr-row { max-width: 100%; font-size: 15px; line-height: 1.35; color: #fff; text-shadow: 0 1px 2px rgba(0,0,0,.7); padding: 5px 9px; border-radius: 12px; background: rgba(0,0,0,.28); backdrop-filter: blur(2px); width: fit-content; word-break: break-word; }
.mlr-row.is-chat .who { font-weight: 700; color: #93c5fd; margin-right: 5px; }
.mlr-row.is-chat .who.seller { color: #6ee7b7; }
.mlr-row.is-chat .badge-seller { font-size: 9px; background: #10b981; color: #04120c; padding: 1px 4px; border-radius: 5px; margin-left: 4px; font-weight: 800; }
.mlr-row.is-bid { background: linear-gradient(90deg, rgba(21,94,239,.94), rgba(18,66,200,.9)); font-weight: 700; display: flex; align-items: center; gap: 6px; }
.mlr-row.is-bid i { color: #ffe08a; }
.mlr-row.is-bid .who { font-weight: 800; }
.mlr-row.is-bid .act { opacity: .85; font-weight: 500; }
.mlr-row.is-bid .amt { margin-left: 4px; background: rgba(255,255,255,.22); padding: 1px 7px; border-radius: 8px; font-weight: 800; }

.mlr-bottom { position: absolute; left: 0; right: 0; bottom: 0; z-index: 7; padding: 10px 12px calc(env(safe-area-inset-bottom, 0px) + 12px); background: linear-gradient(to top, rgba(0,0,0,.72), transparent); }
.mlr-confirm { display: flex; align-items: center; justify-content: space-between; gap: 10px; background: rgba(0,0,0,.55); backdrop-filter: blur(10px); border: 1px solid rgba(255,255,255,.14); border-radius: 14px; padding: 10px 12px; color: #fff; font-size: 13px; }
.mlr-confirm-btns { display: flex; gap: 8px; }
.mlr-btn { border: none; border-radius: 10px; padding: 8px 14px; font-weight: 700; font-size: 13px; cursor: pointer; }
.mlr-btn.ghost { background: rgba(255,255,255,.14); color: #fff; }
.mlr-btn.go { background: #155EEF; color: #fff; display: inline-flex; align-items: center; gap: 5px; }
.mlr-chips { display: flex; gap: 8px; margin-bottom: 8px; }
.mlr-chip { flex: 1; background: rgba(0,0,0,.45); backdrop-filter: blur(8px); border: 1px solid rgba(255,255,255,.16); color: #fff; border-radius: 10px; padding: 8px 4px; font-size: 13px; font-weight: 700; cursor: pointer; }
.mlr-chip:active { background: rgba(21,94,239,.6); }
.mlr-err { color: #fca5a5; font-size: 12px; margin-bottom: 6px; text-shadow: 0 1px 2px rgba(0,0,0,.7); }
.mlr-input-row { display: flex; align-items: center; gap: 8px; }
.mlr-toggle { display: flex; background: rgba(0,0,0,.5); backdrop-filter: blur(8px); border-radius: 12px; padding: 3px; }
.mlr-toggle button { border: none; background: transparent; color: rgba(255,255,255,.65); font-size: 13px; font-weight: 700; padding: 6px 10px; border-radius: 9px; cursor: pointer; }
.mlr-toggle button.on { background: #fff; color: #111; }
.mlr-input { flex: 1; min-width: 0; height: 42px; border-radius: 22px; border: 1px solid rgba(255,255,255,.18); background: rgba(0,0,0,.45); backdrop-filter: blur(8px); color: #fff; padding: 0 16px; font-size: 14px; outline: none; }
.mlr-input::placeholder { color: rgba(255,255,255,.5); }
.mlr-send { width: 42px; height: 42px; border-radius: 50%; border: none; background: #155EEF; color: #fff; font-size: 16px; display: flex; align-items: center; justify-content: center; cursor: pointer; flex-shrink: 0; }
.mlr-send:disabled { opacity: .6; }
.mlr-login { display: block; text-align: center; background: #155eef; color: #fff; padding: 12px; border-radius: 22px; font-weight: 700; text-decoration: none; }
.mlr-note { text-align: center; color: rgba(255,255,255,.7); font-size: 12px; padding: 10px; }
</style>
