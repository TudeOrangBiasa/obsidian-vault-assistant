# Google Calendar API Setup

The vault assistant can sync GitHub issues with due dates to Google Calendar as all-day events. This guide walks through the Google Cloud setup.

## What You Need

- A Google account
- A GitHub repo with issues tagged `due:YYYY-MM-DD`

## Step 1: Create a Google Cloud Project

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Click the project dropdown at the top → **New Project**
3. Name it something like "Vault Assistant"
4. Click **Create**
5. Select the new project from the dropdown

## Step 2: Enable the Calendar API

1. In your project, go to **APIs & Services** → **Library**
2. Search for "Google Calendar API"
3. Click on it → **Enable**

## Step 3: Configure OAuth Consent Screen

1. Go to **APIs & Services** → **OAuth consent screen**
2. Choose **External** (unless you have Google Workspace)
3. Fill in:
   - App name: "Vault Assistant"
   - User support email: your email
   - Developer contact: your email
4. Click **Save and Continue**
5. **Scopes**: Click **Add or Remove Scopes**, search for "Calendar" and select:
   - `.../auth/calendar.readonly` (to read events)
   - `.../auth/calendar.events` (to create events)
6. Click **Save and Continue**
7. **Test users**: Add your email address as a test user
8. Click **Save and Continue**

## Step 4: Create OAuth Credentials

1. Go to **APIs & Services** → **Credentials**
2. Click **Create Credentials** → **OAuth client ID**
3. Application type: **Desktop application**
4. Name: "Vault Assistant CLI"
5. Click **Create**
6. A popup shows your client ID and secret. Click **Download JSON**
7. Save the file as `scripts/client_secret.json` in the vault assistant directory

## Step 5: Run the Auth Flow

```bash
cd obsidian-vault-assistant
python3 scripts/calendar_sync.py --sync
```

This opens a browser window. Sign in with your Google account and grant access. The token saves to `scripts/.calendar-token.json`.

## Step 6: Verify It Works

```bash
python3 scripts/calendar_sync.py --list
```

You should see today's events.

## How It Works

```bash
python3 scripts/calendar_sync.py --sync
```

- Pulls today's events from your primary Google Calendar
- Checks your daily note for an existing Jadwal section
- If section exists and is empty, populates it
- If section has content already, skips to avoid overwrites
- Format: `HH:MM — Event Title` inside a `> [!tip] Jadwal` callout

## Schedule

The daily cron runs this automatically at step 7 (configurable in `config.sh`).

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| `Token expired` | Refresh token missing | Delete `scripts/.calendar-token.json`, re-run `--sync` |
| `No credentials` | Missing client_secret.json | Download from GCP Console → Credentials |
| `Calendar API disabled` | GCP project setup | Enable API at console.cloud.google.com |
| `403 Insufficient Permission` | Wrong OAuth scope | Delete token, re-auth with correct scopes |
| Browser doesn't open | Headless environment | Run `--sync` with `--auth` flag for manual token entry |

## Files

| File | Purpose | Git? |
|------|---------|------|
| `client_secret.json` | OAuth client credentials | No (secret) |
| `.calendar-token.json` | OAuth token (auto-generated) | No (secret) |
| `calendar_sync.py` | Sync script | Yes |

Both secret files are in `.gitignore` so you never accidentally commit them.
