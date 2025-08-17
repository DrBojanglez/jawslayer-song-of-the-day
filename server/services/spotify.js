
import fetch from 'node-fetch';
import { config } from '../config.js';
import { logger } from '../logger.js';

let tokenCache = { token: null, expiresAt: 0 };

async function getToken() {
  const now = Date.now();
  if (tokenCache.token && now < tokenCache.expiresAt) return tokenCache.token;

  const res = await fetch('https://accounts.spotify.com/api/token', {
    method: 'POST',
    headers: {
      Authorization:
        'Basic ' +
        Buffer.from(`${config.SPOTIFY_CLIENT_ID}:${config.SPOTIFY_CLIENT_SECRET}`).toString('base64'),
      'Content-Type': 'application/x-www-form-urlencoded'
    },
    body: new URLSearchParams({ grant_type: 'client_credentials' })
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Spotify token error ${res.status}: ${text}`);
  }

  const data = await res.json();
  tokenCache = {
    token: data.access_token,
    expiresAt: Date.now() + (data.expires_in - 60) * 1000
  };
  return tokenCache.token;
}

export async function fetchAllPlaylistTracks(playlistId) {
  const token = await getToken();
  const base = `https://api.spotify.com/v1/playlists/${encodeURIComponent(playlistId)}/tracks`;
  let url = `${base}?limit=100&fields=items(track(name,external_urls,artists(name),id,album(images))),next`;

  const tracks = [];
  while (url) {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`Spotify tracks error ${res.status}: ${text}`);
    }
    const data = await res.json();
    for (const it of data.items ?? []) {
      const t = it.track;
      if (!t) continue;
      tracks.push({
        id: t.id,
        name: t.name,
        url: t.external_urls?.spotify ?? null,
        artists: (t.artists ?? []).map((a) => a.name).join(', '),
        image: t.album?.images?.[0]?.url ?? null
      });
    }
    url = data.next;
  }

  if (tracks.length === 0) {
    logger.warn('Playlist yielded 0 tracks (is it public and non-empty?)');
    throw new Error('No tracks found in playlist');
  }
  return tracks;
}
