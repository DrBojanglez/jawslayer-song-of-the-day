
import cron from 'node-cron';
import { config } from './config.js';
import { logger } from './logger.js';
import { fetchAllPlaylistTracks } from './services/spotify.js';
import { pickSong } from './services/songPicker.js';
import { postToChannel } from './services/poster.js';

export function scheduleDaily(discord) {
  cron.schedule(
    config.CRON_EXPR,
    async () => {
      try {
        const tracks = await fetchAllPlaylistTracks(config.SPOTIFY_PLAYLIST_ID);
        const track = pickSong(tracks);
        for (const channelId of config.CHANNEL_IDS) {
          await postToChannel(discord, channelId, track);
        }
      } catch (err) {
        logger.error(err, 'Daily job failed');
      }
    },
    { timezone: config.CRON_TZ }
  );
  logger.info({ expr: config.CRON_EXPR, tz: config.CRON_TZ }, 'Scheduled daily job');
}
