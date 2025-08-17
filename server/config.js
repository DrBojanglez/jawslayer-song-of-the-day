
import 'dotenv/config';
import { z } from 'zod';

const schema = z.object({
  DISCORD_TOKEN: z.string().min(1),
  DISCORD_GUILD_ID: z.string().min(1),
  DISCORD_CHANNEL_IDS: z.string().min(1),
  SPOTIFY_CLIENT_ID: z.string().min(1),
  SPOTIFY_CLIENT_SECRET: z.string().min(1),
  SPOTIFY_PLAYLIST_ID: z.string().min(1),
  CRON_TZ: z.string().default('Europe/London'),
  CRON_EXPR: z.string().default('0 6 * * *'),
  PICKER_MODE: z.enum(['hash', 'sequential']).default('hash'),
  STATE_FILE: z.string().default('./state/rotation.json'),
  LOG_LEVEL: z.enum(['trace', 'debug', 'info', 'warn', 'error', 'fatal']).default('info')
});

const parsed = schema.safeParse(process.env);
if (!parsed.success) {
  console.error('❌ Invalid configuration:', parsed.error.flatten().fieldErrors);
  process.exit(1);
}

const raw = parsed.data;
export const config = {
  ...raw,
  CHANNEL_IDS: raw.DISCORD_CHANNEL_IDS.split(',').map((s) => s.trim()).filter(Boolean)
};
