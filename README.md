
# JawSlayer SongOfTheDay

A tiny Discord bot that posts a **Song of the Day** from your **public Spotify playlist** every day at **6:00 AM Liverpool time** (default). Also includes `/songtoday` to trigger a post on demand.

## Features

- ⏰ **Schedules** at your chosen cron (default `0 6 * * *`, Europe/London)
- 🧮 Deterministic or Sequential picks (`PICKER_MODE=hash|sequential`)
- 🧩 **Modular** code: swap picker, message, or schedule without touching everything
- 🧵 Multi-channel: post to multiple channels with `DISCORD_CHANNEL_IDS`
- 🔐 No user login: uses Spotify **Client Credentials** for public playlists
- 🪵 Structured logging

---

## Quick start

1. **Install deps**
   ```bash
   npm i
   ```

2. **Create `.env`** (copy from `.env.example`) and fill in values.

3. **Register commands** (guild-scoped for instant availability)
   ```bash
   npm run register:commands
   ```

4. **Run the bot**
   ```bash
   npm run dev
   ```

Invite the bot to your server with **Send Messages** and **Embed Links** permissions.

---

## Configuration

| Env var | Default | Description |
|---|---|---|
| `DISCORD_TOKEN` | – | Bot token |
| `DISCORD_GUILD_ID` | – | Guild to register commands against |
| `DISCORD_CHANNEL_IDS` | – | Comma-separated channel IDs to post into |
| `SPOTIFY_CLIENT_ID` | – | Spotify app client id |
| `SPOTIFY_CLIENT_SECRET` | – | Spotify app secret |
| `SPOTIFY_PLAYLIST_ID` | – | Public playlist id |
| `CRON_TZ` | `Europe/London` | Timezone for job |
| `CRON_EXPR` | `0 6 * * *` | Cron (6:00 daily) |
| `PICKER_MODE` | `hash` | `hash` (stable per day) or `sequential` (rotates, persisted) |
| `STATE_FILE` | `./state/rotation.json` | Used in sequential mode |
| `LOG_LEVEL` | `info` | `trace`..`error` |

### Change the time
Update `CRON_EXPR` while keeping `CRON_TZ`. Example 9:30 daily:
```
CRON_EXPR=30 9 * * *
```

---

## How it works

- `server/services/spotify.js` pulls your playlist across pages with a cached bearer token.
- `server/services/songPicker.js` chooses a track using either deterministic hashing of the UK date (`hash`) or an on-disk pointer (`sequential`).
- `server/services/poster.js` formats and posts the message (with artwork).
- `server/scheduler.js` runs the job on the cron you specify (BST/GMT handled by `CRON_TZ`).
- `server/bot.js` wires Discord client + `/songtoday`.

---

## Docker

```bash
docker compose up --build -d
```

> The `state/` folder is volume-mounted so sequential mode persists.

---

## Troubleshooting

- **“No tracks found in playlist”**: Ensure the playlist is public and has items.
- **Nothing posts at 6 AM**: Check `CRON_TZ`, bot permissions, and logs. Run `/songtoday` to test.
- **Wrong channel**: Verify `DISCORD_CHANNEL_IDS` and that the bot can post there.
- **Sequential mode doesn’t advance**: Delete `state/rotation.json` or ensure the container has the volume mounted.

---

## License

MIT © You
