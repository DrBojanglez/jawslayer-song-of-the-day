
import { Client, GatewayIntentBits } from 'discord.js';
import { command as songtoday } from './commands/songtoday.js';
import { logger } from './logger.js';

export function createBot() {
  const discord = new Client({ intents: [GatewayIntentBits.Guilds] });

  discord.once('ready', () => {
    logger.info({ user: discord.user.tag }, 'Discord bot ready');
  });

  const handlers = new Map([[songtoday.name, songtoday]]);

  discord.on('interactionCreate', async (interaction) => {
    if (!interaction.isChatInputCommand()) return;
    const cmd = handlers.get(interaction.commandName);
    if (!cmd) return;
    try {
      await cmd.handle(interaction, discord, logger);
    } catch (err) {
      logger.error(err, 'Command handler error');
      if (interaction.deferred || interaction.replied) {
        await interaction.editReply('Command failed.');
      } else {
        await interaction.reply({ content: 'Command failed.', ephemeral: true });
      }
    }
  });

  return discord;
}
