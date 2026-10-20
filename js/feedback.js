let ctx = null;
let lastTickAt = 0;
let voicesWarmed = false;

const ONES = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine',
  'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen',
  'seventeen', 'eighteen', 'nineteen',
];
const TENS = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety'];

export const NUMBER_WORDS = [...ONES, 'twenty'];

const MIN_TICK_GAP_MS = 45;

export async function unlockAudio() {
  try {
    if (!ctx) {
      const AC = (typeof window !== 'undefined' && (window.AudioContext || window.webkitAudioContext)) || null;
      if (!AC) return false;
      ctx = new AC();
    }
    if (ctx.state === 'suspended' && typeof ctx.resume === 'function') await ctx.resume();
    return ctx.state === 'running';
  } catch (err) {
    void err;
    return false;
  }
}

function blip(freq, startAt, ms, gain, type) {
  if (!ctx || ctx.state !== 'running') return false;
  if (gain <= 0 || ms <= 0) return false;
  try {
    const dur = ms / 1000;
    const osc = ctx.createOscillator();
    const g = ctx.createGain();
    osc.type = type || 'sine';
    osc.frequency.setValueAtTime(freq, startAt);
    const peak = Math.max(gain, 0.0005);
    const attack = Math.min(0.008, dur * 0.3);
    const holdEnd = startAt + Math.max(dur - attack, dur * 0.7);
    g.gain.setValueAtTime(0.0001, startAt);
    g.gain.exponentialRampToValueAtTime(peak, startAt + attack);
    g.gain.setValueAtTime(peak, holdEnd);
    g.gain.exponentialRampToValueAtTime(0.0001, startAt + dur);
    osc.connect(g);
    g.connect(ctx.destination);
    osc.start(startAt);
    osc.stop(startAt + dur + 0.02);
    osc.onended = () => {
      try { osc.disconnect(); g.disconnect(); } catch (err) { void err; }
    };
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function playBeep({ freq = 880, ms = 60, gain = 0.05, type = 'sine' } = {}) {
  if (!ctx || ctx.state !== 'running') return false;
  return blip(freq, ctx.currentTime, ms, gain, type);
}

export function playCountTick() {
  const now = (typeof performance !== 'undefined' ? performance.now() : Date.now());
  if (now - lastTickAt < MIN_TICK_GAP_MS) return false;
  lastTickAt = now;
  return blip(440, ctx ? ctx.currentTime : 0, 45, 0.045, 'triangle');
}

export function playWarning() {
  if (!ctx || ctx.state !== 'running') return false;
  const t = ctx.currentTime;
  const a = blip(392, t, 80, 0.035, 'sine');
  const b = blip(294, t + 0.11, 110, 0.03, 'sine');
  return a || b;
}

export function playGo() {
  if (!ctx || ctx.state !== 'running') return false;
  const t = ctx.currentTime;
  const a = blip(659, t, 90, 0.05, 'sine');
  const b = blip(988, t + 0.12, 160, 0.05, 'sine');
  return a || b;
}

function warmVoices() {
  if (voicesWarmed || typeof window === 'undefined' || !window.speechSynthesis) return;
  voicesWarmed = true;
  try {
    window.speechSynthesis.getVoices();
    window.speechSynthesis.addEventListener('voiceschanged', () => {
      window.speechSynthesis.getVoices();
    }, { once: true });
  } catch (err) {
    void err;
  }
}

export function voiceSupported() {
  return typeof window !== 'undefined'
    && 'speechSynthesis' in window
    && typeof window.SpeechSynthesisUtterance === 'function';
}

export function speak(text, { interrupt = true, rate = 1, pitch = 1 } = {}) {
  if (!voiceSupported() || text === undefined || text === null || text === '') return false;
  warmVoices();
  const syn = window.speechSynthesis;
  try {
    if (interrupt) {
      if (syn.speaking || syn.pending) syn.cancel();
    } else if (syn.speaking) {
      return false;
    }
    const u = new window.SpeechSynthesisUtterance(String(text));
    u.rate = rate;
    u.pitch = pitch;
    u.volume = 1;
    u.lang = (navigator.language || 'en-US');
    syn.speak(u);
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function stopSpeaking() {
  if (!voiceSupported()) return false;
  try {
    window.speechSynthesis.cancel();
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function vibrate(pattern) {
  if (typeof navigator === 'undefined' || typeof navigator.vibrate !== 'function') return false;
  try {
    navigator.vibrate(pattern === undefined ? 12 : pattern);
    return true;
  } catch (err) {
    void err;
    return false;
  }
}

export function countWord(n) {
  const num = Math.trunc(Number(n));
  if (!Number.isFinite(num) || num < 0 || num > 999) return String(n);
  if (num < 20) return ONES[num];
  const tens = Math.floor(num / 10);
  const rest = num % 10;
  if (tens < 10) return rest === 0 ? TENS[tens] : `${TENS[tens]}-${ONES[rest]}`;
  const hundreds = Math.floor(num / 100);
  const tail = num % 100;
  if (tail === 0) return `${ONES[hundreds]} hundred`;
  return `${ONES[hundreds]} hundred ${countWord(tail)}`;
}

export function announceRep(n, { mode = 'every', voice = true, beeps = true, haptics = true } = {}) {
  const count = Math.trunc(Number(n)) || 0;
  let spoke = false;
  if (voice && mode !== 'off' && (mode === 'every' || count % 5 === 0)) {
    spoke = speak(countWord(count), { interrupt: true });
  }
  const ticked = beeps ? playCountTick() : false;
  const buzzed = haptics ? vibrate(count % 5 === 0 ? [18, 40, 18] : 12) : false;
  return { spoke, ticked, buzzed };
}

export function countdownVoice(secondsLeft) {
  const words = { 5: 'five', 4: 'four', 3: 'three', 2: 'two', 1: 'one' };
  const s = Math.trunc(Number(secondsLeft));
  if (!Number.isFinite(s) || s <= 0) return 'go';
  return words[s] || countWord(s);
}
