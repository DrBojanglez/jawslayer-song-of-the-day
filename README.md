# JawSlayer SongOfTheDay

Post a daily “Song of the Day” from your public Spotify playlist to Discord, automatically at 06:00 Europe/London time (BST/GMT-aware), and also via `/songtoday` command.

---

## 1. Overview & Integration

**Discord Bot Setup**

* Create a Discord Application & Bot in the [Developer Portal](https://discord.com/developers/docs/quick-start).
* Invite it to your server with permissions: *View Channel*, *Send Messages*, *Embed Links*.
* Use the provided `client/register-commands.js` to register the `/songtoday` command for your server (guild scope for instant availability).

**How to post**

* Bot will automatically post every day at the scheduled time.
* Manually trigger with `/songtoday`.

---

## 2. Requirements

* Node.js v20+ (or via Docker).
* `discord.js`, `node-cron`, `dotenv`, etc. installed via `npm install`.
* **Discord Bot Token** and **Spotify App credentials** (Client ID + Secret) with a **public** Spotify playlist.
* Confirmed `.env` configuration (see below).

---

## 3. Configuration (`.env`)

Copy `.env.example` → `.env` and fill in:

| Variable                                      | Function                                                 |
| --------------------------------------------- | -------------------------------------------------------- |
| `DISCORD_TOKEN`                               | Bot token from Developer Portal                          |
| `DISCORD_GUILD_ID`                            | Discord server ID (for registering slash commands)       |
| `DISCORD_CHANNEL_IDS`                         | Channels to post into (comma-separated)                  |
| `SPOTIFY_CLIENT_ID` / `SPOTIFY_CLIENT_SECRET` | Spotify API credentials                                  |
| `SPOTIFY_PLAYLIST_ID`                         | ID of your public Spotify playlist                       |
| `CRON_TZ`                                     | Timezone (default `Europe/London`)                       |
| `CRON_EXPR`                                   | Cron schedule (default `0 6 * * *`)                      |
| `PICKER_MODE`                                 | `hash` (deterministic) or `sequential`                   |
| `STATE_FILE`                                  | Storage file for sequential mode (`state/rotation.json`) |
| `LOG_LEVEL`                                   | Logging level (e.g., `info`, `debug`)                    |

---

## 4. Local Usage

```bash
npm install
npm run register:commands
npm run dev
```

* Slash commands should appear instantly (guild-scoped).
* Use `/songtoday` to test.
* Check console logs for runtime errors or scheduling issues.

---

## 5. Deployment Options

### A) systemd (Ubuntu/Debian VPS)

Reliable and auto-restarts on crash or reboot.

1. Place code in `/opt/jawslayer` (or appropriate path), install deps via `npm ci --omit=dev`.
2. Create a service at `/etc/systemd/system/jawslayer.service`:

   ```ini
   [Unit]
   Description=JawSlayer SongOfTheDay Bot
   After=network.target

   [Service]
   User=youruser
   WorkingDirectory=/opt/jawslayer
   ExecStart=/usr/bin/node server/index.js
   Restart=on-failure

   [Install]
   WantedBy=multi-user.target
   ```
3. Enable and start:

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now jawslayer
   sudo systemctl status jawslayer
   ```
4. Logs: `journalctl -u jawslayer -f`.

*(Based on systemd examples for Discord bots and service management.)* ([Gist][1])

---

### B) PM2 (Process Manager)

1. Install PM2:

   ```bash
   npm install -g pm2
   ```
2. Start bot via PM2:

   ```bash
   pm2 start server/index.js --name jawslayer
   ```
3. Persist setup on reboot:

   ```bash
   pm2 save
   pm2 startup
   ```
4. Control bot:

   * `pm2 list` — view status
   * `pm2 logs jawslayer` — tail logs
   * `pm2 restart jawslayer` — restart
   * `pm2 stop jawslayer` — stop

*(Follows PM2 Quick Start and Discord bot usage guidance.)* ([Discord.js Guide][2], [Medium][3], [Medium][4])

---

### C) Docker / Docker Compose

* Run with:

  ```bash
  docker compose up --build -d
  ```
* The `state/` folder is volume-mounted to preserve rotation state.

Many community users deploy bots via Docker to ensure uptime—even on low-cost hardware. ([Gist][1], [Reddit][5])

---

## 6. After Creating the Server

1. Set up `.env`, install dependencies, and test locally.
2. Register slash commands with `npm run register:commands`.
3. Choose a deployment method:

   * *For VPS/systemd or PM2*: clone repo, install, and start as above.
   * *For Docker*: build and run with Compose.
4. Ensure bot has permissions and can post in channels.
5. Monitor logs and test manually with `/songtoday`.

---

## 7. Troubleshooting

| Issue                 | Fix                                                                         |
| --------------------- | --------------------------------------------------------------------------- |
| No tracks found       | Verify playlist is public and not empty.                                    |
| Slash command missing | Re-run registration, check `DISCORD_GUILD_ID`, ensure bot is in your guild. |
| Posts not appearing   | Check bot permissions, logs, and that scheduler is running.                 |
| Invalid credentials   | Confirm `.env` values and regenerate tokens if needed.                      |

---

### Key References

* \[Systemd service setup for bots]\([Better Stack][6], [Discord.js Guide][2], [YouTube][7], [Gist][1])
* \[PM2 process management guide]\([Discord.js Guide][2])
* \[Reddit: Docker for bot uptime]\([Reddit][5])

[1]: https://gist.github.com/comhad/de830d6d1b7ae1f165b925492e79eac8?utm_source=chatgpt.com "How to setup a systemctl service for running your bot on ..."
[2]: https://discordjs.guide/improving-dev-environment/pm2?utm_source=chatgpt.com "Managing your bot process with PM2"
[3]: https://medium.com/%40a_farag/deploying-a-node-js-project-with-pm2-in-production-mode-fc0e794dc4aa?utm_source=chatgpt.com "Deploying a Node.js Project with PM2 in Production Mode"
[4]: https://medium.com/%40ayushnandanwar003/deploying-node-js-applications-using-pm2-a-detailed-guide-b8b6d55dfc88?utm_source=chatgpt.com "Deploying Node.js Applications Using PM2: A Detailed Guide"
[5]: https://www.reddit.com/r/Discord_Bots/comments/1hk8i5k/how_are_bots_usually_hosted/?utm_source=chatgpt.com "How are bots usually hosted? : r/Discord_Bots"
[6]: https://betterstack.com/community/guides/scaling-nodejs/pm2-guide/?utm_source=chatgpt.com "Running Node.js Apps with PM2 (Complete Guide)"
[7]: https://www.youtube.com/watch?v=qv24S2L1N0k&utm_source=chatgpt.com "How To Build And Deploy Your First Discord Bot"
