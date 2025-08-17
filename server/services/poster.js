
import { ChannelType } from 'discord.js';

function renderMessage(track) {
  const title = `🎵 Song of the Day`;
  const line = `**${track.name}** — ${track.artists}\n${track.url ?? ''}`;
  return `${title}\n${line}`;
}

export async function postToChannel(discord, channelId, track) {
  const channel = await discord.channels.fetch(channelId);
  if (!channel || (channel.type !== ChannelType.GuildText && channel.type !== ChannelType.GuildAnnouncement)) {
    throw new Error(`Channel ${channelId} is not a writable text/news channel`);
  }
  const content = renderMessage(track);
  const payload = track.image ? { content, embeds: [{ image: { url: track.image } }] } : { content };
  await channel.send(payload);
}
