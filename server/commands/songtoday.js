
import { fetchAllPlaylistTracks } from '../services/spotify.js';
import { pickSong } from '../services/songPicker.js';
import { config } from '../config.js';
import { postToChannel } from '../services/poster.js';

export const command = {
  name: 'songtoday',
  description: 'Post the Song of the Day from the configured Spotify playlist.',
  async handle(interaction, discord, logger) {
    await interaction.deferReply({ ephemeral: true });
    try {
      const tracks = await fetchAllPlaylistTracks(config.SPOTIFY_PLAYLIST_ID);
      const track = pickSong(tracks);
      for (const channelId of config.CHANNEL_IDS) {
        await postToChannel(discord, channelId, track);
      }
      await interaction.editReply('Posted today’s song! ✅');
    } catch (e) {
      logger.error(e, 'Slash command failed');
      await interaction.editReply(`Sorry—couldn’t post today’s song: ${e.message}`);
    }
  }
};
