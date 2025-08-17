
# JawSlayer SongOfTheDay

**What it does**
Every day at 06:00 Europe/London time (automatically adjusts for BST/GMT), this bot posts a "Song of the Day" from your public Spotify playlist into specified Discord channel(s). You can also trigger it manually with the `/songtoday` command.

---

## 1. Architecture Overview

* **Spotify Integration**
  Uses the [Client Credentials flow](https://developer.spotify.com/documentation/general/guides/authorization/client-credentials/) to fetch playlist data from a public Spotify playlist.

* **Song Picker**

  * **Hash mode**: Deterministically selects a song based on the current UK date.
  * **Sequential mode**: Rotates through playlist tracks, saving state to disk.

* **Scheduler**
  Runs daily using `node-cron`, respecting `Europe/London` timezone for automatic BST support.

* **Discord Integration**
  Built with `discord.js`. Handles both scheduled and slash-command-triggered posts.
  `/songtoday` posts the current song on demand.

---

## 2. Requirements

* Node.js ≥ 20
* Discord Bot (with token); invited to your server with **Send Messages** and **Embed Links** permissions
* Spotify Developer app (Client ID and Secret)
* A **public** Spotify playlist (private playlists won’t work with Client Credentials)

---

## 3. Configuration

Copy `.env.example` to `.env` and fill out:

| Environment Variable    | Purpose                                                                    |
| ----------------------- | -------------------------------------------------------------------------- |
| `DISCORD_TOKEN`         | Bot token from Discord Developer Portal                                    |
| `DISCORD_GUILD_ID`      | Guild where `/songtoday` is registered                                     |
| `DISCORD_CHANNEL_IDS`   | Comma-separated channel IDs where the bot will post                        |
| `SPOTIFY_CLIENT_ID`     | Spotify Developer app client ID                                            |
| `SPOTIFY_CLIENT_SECRET` | Spotify Developer app client secret                                        |
| `SPOTIFY_PLAYLIST_ID`   | Spotify public playlist ID (from your playlist URL)                        |
| `CRON_TZ`               | Timezone for scheduling (default: `Europe/London`)                         |
| `CRON_EXPR`             | Cron expression for schedule (default: `0 6 * * *`)                        |
| `PICKER_MODE`           | `hash` (default) or `sequential`                                           |
| `STATE_FILE`            | File path for sequential rotation state (default: `./state/rotation.json`) |
| `LOG_LEVEL`             | `trace`, `debug`, `info`, etc.                                             |

---

## 4. Local Setup

1. Install dependencies:

   ```bash
   npm install
   ```
2. Register slash command:

   ```bash
   npm run register:commands
   ```
3. Start the bot:

   ```bash
   npm run dev
   ```

Bot will connect and post at the scheduled time. Use `/songtoday` to test manually.

---

## 5. Deployment Options

### A) systemd (Linux)

1. Configure the bot in a directory (e.g., `/opt/jawslayer-song-of-the-day`) and install dependencies with `npm ci --omit=dev`.
2. Create `/etc/systemd/system/jawslayer.service` with appropriate `ExecStart`, working directory, and restart policy.
3. Run:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now jawslayer.service
   ```
4. To update:

   ```bash
   cd /opt/jawslayer...
   git pull && npm ci --omit=dev
   sudo systemctl restart jawslayer.service
   ```

### B) PM2

```bash
npm install -g pm2
pm2 start server/index.js --name songofday
pm2 save
pm2 startup   # follow instructions to auto-start on reboot
```

---

### C) Docker / Docker Compose

Simply run:

```bash
docker compose up --build -d
```

State persists via the volume-mounted `state/` directory.

---

## 6. Troubleshooting

* **No tracks found**: Make sure the playlist is public and not empty.
* **Commands don’t appear**: Re-run command registration, ensure correct `DISCORD_GUILD_ID`, and bot is in the guild.
* **Posts not appearing**: Check permissions, logs, and that the scheduler is running.
* **Invalid credentials**: Verify `.env` values and regenerate tokens if necessary.

---

## 7. Quick Deploy (PM2 Example)

```bash
git clone https://github.com/<your-username>/jawslayer-song-of-the-day.git
cd jawslayer-song-of-the-day
cp .env.example .env  # fill in
npm ci --omit=dev
npm run register:commands
npm i -g pm2 && pm2 start server/index.js --name songofday && pm2 save && pm2 startup
```

