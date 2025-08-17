# JawSlayer SongOfTheDay - Complete Walkthrough

This guide walks you step-by-step through creating, configuring, and hosting your Discord bot that posts a daily song from your Spotify playlist. No prior knowledge assumed—integration explained from the ground up.

---

## 1. What You’ll Need

### Hardware & OS

* A computer or server running **Ubuntu 22.04 LTS** or **Ubuntu 24.04 LTS** (common, stable Linux versions). (\[DigitalOcean install guide]\([DigitalOcean][1]))
* At least **4 GB RAM**, **20 GB disk space**, and internet access. Node.js runs fine on modest cloud instances.

### Software Requirements

* **Node.js v20 LTS** (JavaScript runtime).
* **npm** (Node package manager).
* **Git**, **curl**, **build-essential** (for setting up the environment).
* Discord developer account and Spotify developer account.
* Access to your Spotify playlist (must be **public**).

---

## 2. Install Prerequisites on Ubuntu

### 2.1 Update system and install basics:

```bash
sudo apt update
sudo apt install -y curl ca-certificates gnupg build-essential git
```

### 2.2 Install Node.js v20 (preferred production method via NodeSource):

```bash
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
  | sudo tee /etc/apt/sources.list.d/nodesource.list
sudo apt update
sudo apt install -y nodejs
```

This provides up-to-date, supported Node.js binaries. (\[DigitalOcean guide]\([DigitalOcean][2]))

Alternatively, use **NVM**, especially if you plan to manage multiple Node versions:

```bash
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh \
  | bash
source ~/.bashrc
nvm install 20
```

(\[AskUbuntu guide]\([Ask Ubuntu][3]))

Verify:

```bash
node -v  # Should show v20.x
npm -v   # Should show matching version
```

---

## 3. Set Up Discord Bot

### 3.1 Create the Bot Application:

1. Visit the **Discord Developer Portal**.
2. Click **New Application**, give it a name.
3. Navigate to Bot → click **Add Bot**, confirm.
4. Copy the **Bot Token** (we’ll use it later).

### 3.2 Invite the bot to your server:

1. Go to OAuth2 → URL Generator.
2. Under Scopes: select **bot**, and if using slash commands, **applications.commands**.
3. Under Bot Permissions: choose *Send Messages*, *Embed Links*.
4. Copy the generated URL, open it in your browser, and invite the bot to your server.

---

## 4. Set Up Spotify Credentials and Playlist

1. Go to the \[Spotify Developer Dashboard] and create a new app.
2. Copy the **Client ID** and **Client Secret**.
3. Ensure your Spotify playlist is **public**, or the bot can’t access it.

---

## 5. Project Setup

### 5.1 Clone or create project:

```bash
git clone https://github.com/<your-username>/jawslayer-song-of-the-day.git
cd jawslayer-song-of-the-day
```

### 5.2 Install dependencies:

```bash
npm install
```

### 5.3 Configure environment:

```bash
cp .env.example .env
```

Edit `.env` and populate:

* `DISCORD_TOKEN` with your bot token.
* `DISCORD_GUILD_ID` with your server’s ID.
* `DISCORD_CHANNEL_IDS` with IDs of channels where bot should post.
* `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET`, and `SPOTIFY_PLAYLIST_ID`.
* Leave defaults for schedule/timezone unless you want to change them.

---

## 6. Register Slash Command `/songtoday`

Run:

```bash
npm run register:commands
```

This registers your slash command **for your server only** (guild-scoped), so updates appear instantly with no delay. (\[Discord.js guild commands]\([Discord.js Guide][4], [Deno][5], [Medium][6]))

---

### 7. Run the Bot Locally for the First Time

```bash
npm run dev
```

Check terminal for successful login and scheduled job setup. Use `/songtoday` in Discord to trigger a manual post and verify everything works.

---

## 8. Deploy the Bot to a Server (Production)

Choose one method below:

### Option A: systemd (recommended for stable server runs)

Create a systemd service:

```ini
[Unit]
Description=JawSlayer SongOfTheDay Bot
After=network.target

[Service]
User=youruser
WorkingDirectory=/home/youruser/jawslayer-song-of-the-day
ExecStart=/usr/bin/node server/index.js
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

```bash
sudo tee /etc/systemd/system/jawslayer.service > /dev/null <<EOF
[Unit]
Description=JawSlayer SongOfTheDay Bot
After=network.target

[Service]
User=$USER
WorkingDirectory=$(pwd)
ExecStart=$(which node) server/index.js
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now jawslayer
sudo journalctl -f -u jawslayer
```

Solid, reliable deployment. (\[systemd best practices]\([Deno][5], [Discord.js Guide][7], [Vultr Docs][8]))

---

### Option B: PM2 (process manager for Node)

```bash
sudo npm install -g pm2
pm2 start server/index.js --name jawslayer
pm2 save
pm2 startup
pm2 logs jawslayer
```

Easy to manage restart, logs, and startup behavior.

---

### Option C: Docker (containerized)

```bash
docker compose up --build -d
```

This container runs your bot and preserves state across restarts via volume. Great for cloud deployments.

---

## 9. Ongoing Management

* After changes: `git pull && npm ci --omit=dev && sudo systemctl restart jawslayer` (systemd) or `pm2 restart jawslayer`
* Logs:

  * systemd: `sudo journalctl -u jawslayer -f`
  * PM2: `pm2 logs jawslayer`

---

## 10. Troubleshooting Tips

| Problem                    | Solution                                                         |
| -------------------------- | ---------------------------------------------------------------- |
| Slash command doesn’t show | Ensure `DISCORD_GUILD_ID` is correct and run `register:commands` |
| No song posted             | Check playlist is public, bot has permissions, and schedule logs |
| Spotify/Bot login fails    | Double-check tokens in `.env` and server logs                    |

---


[1]: https://www.digitalocean.com/community/tutorials/how-to-install-node-js-on-ubuntu-22-04?utm_source=chatgpt.com "How to Install Node.js on Ubuntu (Step-by-Step Guide)"
[2]: https://www.digitalocean.com/community/tutorials/how-to-install-node-js-on-ubuntu-20-04?utm_source=chatgpt.com "How to Install Node.js on Ubuntu"
[3]: https://askubuntu.com/questions/1502744/how-to-install-node-js-latest-version-on-ubuntu-22-04?utm_source=chatgpt.com "How to install Node JS latest version on Ubuntu 22.04?"
[4]: https://discordjs.guide/creating-your-bot/command-deployment?utm_source=chatgpt.com "Registering slash commands"
[5]: https://docs.deno.com/deploy/tutorials/discord-slash/?utm_source=chatgpt.com "Discord Slash Command"
[6]: https://medium.com/%40nsidana123/before-the-birth-of-of-node-js-15ee9262110c?utm_source=chatgpt.com "How To Install Node.js 20 LTS on Ubuntu 22.04|20.04|18.04"
[7]: https://discordjs.guide/creating-your-bot/slash-commands?utm_source=chatgpt.com "Creating slash commands"
[8]: https://docs.vultr.com/installing-node-js-and-express-on-ubuntu-20-04?utm_source=chatgpt.com "Installing Node.js and Express on Ubuntu 20.04"
