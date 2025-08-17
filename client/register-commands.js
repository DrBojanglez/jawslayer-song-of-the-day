
import 'dotenv/config';
import { REST, Routes, SlashCommandBuilder } from 'discord.js';

const { DISCORD_TOKEN, DISCORD_GUILD_ID } = process.env;
if (!DISCORD_TOKEN || !DISCORD_GUILD_ID) {
  console.error('Missing DISCORD_TOKEN or DISCORD_GUILD_ID in .env');
  process.exit(1);
}

const commands = [
  new SlashCommandBuilder().setName('songtoday').setDescription('Post today’s song.').toJSON()
];

const rest = new REST({ version: '10' }).setToken(DISCORD_TOKEN);

async function main() {
  const app = await rest.get(Routes.oauth2CurrentApplication());
  await rest.put(Routes.applicationGuildCommands(app.id, DISCORD_GUILD_ID), { body: commands });
  console.log('Slash commands registered. ✅');
}
main().catch((err) => {
  console.error('Failed to register commands:', err);
  process.exit(1);
});
