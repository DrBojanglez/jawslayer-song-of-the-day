
import crypto from 'node:crypto';
import { config } from '../config.js';
import fs from 'fs-extra';

function ukDateKey() {
  const nowUK = new Date(new Date().toLocaleString('en-GB', { timeZone: 'Europe/London' }));
  const yyyy = nowUK.getFullYear();
  const mm = String(nowUK.getMonth() + 1).padStart(2, '0');
  const dd = String(nowUK.getDate()).padStart(2, '0');
  return `${yyyy}-${mm}-${dd}`;
}

function pickByHash(tracks) {
  const dateKey = ukDateKey();
  const h = crypto.createHash('sha256').update(dateKey).digest('hex');
  const n = parseInt(h.slice(0, 8), 16);
  return tracks[n % tracks.length];
}

function loadState() {
  try {
    return fs.readJsonSync(config.STATE_FILE);
  } catch {
    return { lastIndex: -1, lastDate: null };
  }
}
function saveState(s) {
  fs.ensureFileSync(config.STATE_FILE);
  fs.writeJsonSync(config.STATE_FILE, s, { spaces: 2 });
}

function pickSequential(tracks) {
  const state = loadState();
  const today = ukDateKey();
  const shouldAdvance = state.lastDate !== today;
  const nextIndex = shouldAdvance ? (state.lastIndex + 1) % tracks.length : state.lastIndex % tracks.length;
  const idx = Math.max(0, nextIndex);
  const track = tracks[idx];
  if (shouldAdvance) {
    saveState({ lastIndex: idx, lastDate: today });
  }
  return track;
}

export function pickSong(tracks) {
  return config.PICKER_MODE === 'sequential' ? pickSequential(tracks) : pickByHash(tracks);
}
