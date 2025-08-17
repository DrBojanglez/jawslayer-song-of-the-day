#!/usr/bin/env bash
set -euo pipefail

APP_DIR="jawslayer-song-of-the-day"
APP_TITLE="JawSlayer SongOfTheDay"

if [[ -d "$APP_DIR" ]]; then
  echo "Directory '$APP_DIR' already exists. Aborting to avoid overwriting."
  exit 1
fi

mkdir -p "$APP_DIR"
cd "$APP_DIR"

# ---- git init ---------------------------------------------------------------
git init -q
git branch -M main

# ---- directories ------------------------------------------------------------
mkdir -p server/services server/commands client state .github/workflows

# ---- package.json -----------------------------------------------------------
cat > package.json <<'EOF'
{
  "name": "jawslayer-song-of-the-day",
  "version": "2.0.0",
  "type": "module",
  "main": "server/index.js",
  "scripts": {
    "dev": "nodemon",
    "start": "node server/index.js",
    "register:commands": "node client/register-commands.js",
    "lint": "eslint .",
    "format": "prettier -w .",
    "test": "node -e \"console.log('no tests yet')\""
  },
  "dependencies": {
    "discord.js": "^14.16.3",
    "dotenv": "^16.4.5",
    "fs-extra": "^11.2.0",
    "node-cron": "^3.0.3",
    "node-fetch": "^3.3.2",
    "pino": "^9.4.0",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "eslint": "^9.10.0",
    "eslint-config-prettier": "^9.1.0",
    "eslint-plugin-import": "^2.29.1",
    "nodemon": "^3.1.4",
    "prettier": "^3.3.3"
  }
}
EOF

# ---- .env.example -----------------------------------------------------------
cat > .env.example <<'EOF'
# --- Discord ---
DISCORD_TOKEN=your-bot-token
DISCORD_GUILD_ID=your-guild-id
DISCORD_CHANNEL_IDS=123456789012345678             # comma-separated OK

# --- Spotify (public playlist read via client credentials) ---
SPOTIFY_CLIENT_ID=your-client-id
SPOTIFY_CLIENT_SECRET=your-client-secret
SPOTIFY_PLAYLIST_ID=your-public-playlist-id

# --- Scheduling / picker behavior ---
CRON_TZ=Europe/London
CRON_EXPR=0 6 * * *                                 # 06:00 daily (Liverpool)
PICKER_MODE=hash                                     # hash | sequential
STATE_FILE=./state/rotation.json                     # used when PICKER_MODE=sequential

# --- Optional ---
LOG_LEVEL=info                                       # trace|debug|info|warn|error
EOF

# ---- server/config.js -------------------------------------------------------
cat > server/config.js <<'EOF'
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
EOF

# ---- server/logger.js -------------------------------------------------------
cat > server/logger.js <<'EOF'
import pino from 'pino';
import { config } from './config.js';

export const logger = pino({
  level: config.LOG_LEVEL,
  transport: process.env.NODE_ENV === 'production' ? undefined : { target: 'pino-pretty' }
});
EOF

# ---- server/services/spotify.js --------------------------------------------
cat > server/services/spotify.js <<'EOF'
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
EOF

# ---- server/services/songPicker.js -----------------------------------------
cat > server/services/songPicker.js <<'EOF'
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
EOF

# ---- server/services/poster.js ---------------------------------------------
cat > server/services/poster.js <<'EOF'
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
EOF

# ---- server/commands/songtoday.js ------------------------------------------
cat > server/commands/songtoday.js <<'EOF'
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
EOF

# ---- server/bot.js ----------------------------------------------------------
cat > server/bot.js <<'EOF'
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
EOF

# ---- server/scheduler.js ----------------------------------------------------
cat > server/scheduler.js <<'EOF'
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
EOF

# ---- server/index.js --------------------------------------------------------
cat > server/index.js <<'EOF'
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
EOF

# ---- client/register-commands.js -------------------------------------------
cat > client/register-commands.js <<'EOF'
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
EOF

# ---- README.md --------------------------------------------------------------
cat > README.md <<EOF
# $APP_TITLE

A tiny Discord bot that posts a **Song of the Day** from your **public Spotify playlist** every day at **6:00 AM Liverpool time** (default). Also includes \`/songtoday\` to trigger a post on demand.

## Features

- ⏰ **Schedules** at your chosen cron (default \`0 6 * * *\`, Europe/London)
- 🧮 Deterministic or Sequential picks (\`PICKER_MODE=hash|sequential\`)
- 🧩 **Modular** code: swap picker, message, or schedule without touching everything
- 🧵 Multi-channel: post to multiple channels with \`DISCORD_CHANNEL_IDS\`
- 🔐 No user login: uses Spotify **Client Credentials** for public playlists
- 🪵 Structured logging

---

## Quick start

1. **Clone & install**
   \`\`\`bash
   npm i
   \`\`\`

2. **Create \`.env\`** (copy from \`.env.example\`) and fill in values.

3. **Register commands** (guild-scoped for instant availability)
   \`\`\`bash
   npm run register:commands
   \`\`\`

4. **Run the bot**
   \`\`\`bash
   npm run dev
   \`\`\`

Invite the bot to your server with **Send Messages** and **Embed Links** permissions.

---

## Configuration

| Env var | Default | Description |
|---|---|---|
| \`DISCORD_TOKEN\` | – | Bot token |
| \`DISCORD_GUILD_ID\` | – | Guild to register commands against |
| \`DISCORD_CHANNEL_IDS\` | – | Comma-separated channel IDs to post into |
| \`SPOTIFY_CLIENT_ID\` | – | Spotify app client id |
| \`SPOTIFY_CLIENT_SECRET\` | – | Spotify app secret |
| \`SPOTIFY_PLAYLIST_ID\` | – | Public playlist id |
| \`CRON_TZ\` | \`Europe/London\` | Timezone for job |
| \`CRON_EXPR\` | \`0 6 * * *\` | Cron (6:00 daily) |
| \`PICKER_MODE\` | \`hash\` | \`hash\` (stable per day) or \`sequential\` (rotates, persisted) |
| \`STATE_FILE\` | \`./state/rotation.json\` | Used in sequential mode |
| \`LOG_LEVEL\` | \`info\` | \`trace\`..\`error\` |

### Change the time
Update \`CRON_EXPR\` while keeping \`CRON_TZ\`. Example 9:30 daily:
\`\`\`
CRON_EXPR=30 9 * * *
\`\`\`

---

## How it works

- \`server/services/spotify.js\` pulls your playlist across pages with a cached bearer token.
- \`server/services/songPicker.js\` chooses a track using either deterministic hashing of the UK date (\`hash\`) or an on-disk pointer (\`sequential\`).
- \`server/services/poster.js\` formats and posts the message (with artwork).
- \`server/scheduler.js\` runs the job on the cron you specify (BST/GMT handled by \`CRON_TZ\`).
- \`server/bot.js\` wires Discord client + \`/songtoday\`.

---

## Docker

\`\`\`bash
docker compose up --build -d
\`\`\`

> The \`state/\` folder is volume-mounted so sequential mode persists.

---

## Troubleshooting

- **“No tracks found in playlist”**: Ensure the playlist is public and has items.
- **Nothing posts at 6 AM**: Check \`CRON_TZ\`, bot permissions, and logs. Run \`/songtoday\` to test.
- **Wrong channel**: Verify \`DISCORD_CHANNEL_IDS\` and that the bot can post there.
- **Sequential mode doesn’t advance**: Delete \`state/rotation.json\` or ensure the container has the volume mounted.

---

## License

MIT © You
EOF

# ---- ESLint / Prettier / nodemon / editorconfig ----------------------------
cat > .eslintrc.cjs <<'EOF'
module.exports = {
  env: { es2022: true, node: true },
  extends: ['eslint:recommended', 'plugin:import/recommended', 'prettier'],
  parserOptions: { ecmaVersion: 'latest', sourceType: 'module' },
  rules: { 'import/no-unresolved': 'off' }
};
EOF

cat > .prettierrc <<'EOF'
{
  "singleQuote": true,
  "semi": true,
  "trailingComma": "none",
  "printWidth": 100
}
EOF

cat > nodemon.json <<'EOF'
{
  "watch": ["server", ".env"],
  "ext": "js,json",
  "exec": "node server/index.js"
}
EOF

cat > .editorconfig <<'EOF'
root = true

[*]
charset = utf-8
end_of_line = lf
indent_style = space
indent_size = 2
insert_final_newline = true
trim_trailing_whitespace = true
EOF

# ---- Docker ---------------------------------------------------------------
cat > Dockerfile <<'EOF'
FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
ENV NODE_ENV=production
CMD ["node", "server/index.js"]
EOF

cat > docker-compose.yml <<'EOF'
services:
  bot:
    build: .
    env_file: .env
    restart: unless-stopped
    volumes:
      - ./state:/app/state
EOF

# ---- CI workflow -----------------------------------------------------------
cat > .github/workflows/ci.yml <<'EOF'
name: CI
on:
  push:
  pull_request:

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: npm run lint
      - run: npm run test
EOF

# ---- .gitignore ------------------------------------------------------------
cat > .gitignore <<'EOF'
node_modules
.env
state/*.json
npm-debug.log*
.pnpm-debug.log*
.DS_Store
EOF

# ---- LICENSE ---------------------------------------------------------------
cat > LICENSE <<'EOF'
MIT License

Copyright (c) 2025

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

# ---- state placeholder ------------------------------------------------------
mkdir -p state
echo '{}' > state/rotation.json

# ---- install & first commit -------------------------------------------------
echo "Installing npm dependencies..."
npm install --silent

git add -A
git commit -m "chore: initial release — JawSlayer SongOfTheDay" >/dev/null

cat <<'DONE'

✅ Project created: jawslayer-song-of-the-day

Next steps:
  1) cd jawslayer-song-of-the-day
  2) cp .env.example .env   # fill in tokens/IDs
  3) npm run register:commands
  4) npm run dev            # or: docker compose up --build -d

Optional (push to GitHub):
  git remote add origin git@github.com:<you>/jawslayer-song-of-the-day.git
  git push -u origin main

DONE

