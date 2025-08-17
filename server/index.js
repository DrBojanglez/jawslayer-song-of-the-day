
import { config } from './config.js';
import { logger } from './logger.js';
import { createBot } from './bot.js';
import { scheduleDaily } from './scheduler.js';

async function main() {
  const discord = createBot();
  await discord.login(config.DISCORD_TOKEN);
  scheduleDaily(discord);
}

main().catch((e) => {
  logger.error(e, 'Fatal startup error');
  process.exit(1);
});
