# Setting up the Google OAuth client for Calendar sync

Pantria is self-hosted, so you provide your own Google OAuth credentials (there
is no shared Pantria Google app). This is a one-time setup, ~10–15 minutes.
You'll create a Google Cloud project, enable the Calendar API, make an OAuth
client, and paste its ID + secret into **Calendar → Calendar sync**.

> The exact labels in the Google Cloud Console shift over time (some screens are
> now grouped under **"Google Auth Platform"**). The steps below note both the
> classic and newer names where they differ.

---

## Before you start

- Find your Pantria **redirect URI**. Open **Calendar → Calendar sync** in
  Pantria — it's shown on that page. It's your instance URL + `/calendar_connection/callback`, e.g.
  - Local preview: `http://localhost:3001/calendar_connection/callback`
  - Real deployment: `https://calendar.example.com/calendar_connection/callback`
- You'll register this **exactly** in Google (a trailing-slash or http/https
  mismatch makes Google reject the redirect). For a real (non-localhost)
  deployment Google requires **https**.

---

## 1. Create (or pick) a Google Cloud project

1. Go to <https://console.cloud.google.com/>.
2. Top bar → project dropdown → **New Project** (or reuse an existing one).
3. Name it e.g. `pantria-calendar`, **Create**, then select it.

## 2. Enable the Google Calendar API

1. Left menu → **APIs & Services → Library** (or <https://console.cloud.google.com/apis/library>).
2. Search **Google Calendar API** → open it → **Enable**.

## 3. Configure the OAuth consent screen

1. **APIs & Services → OAuth consent screen** (newer console: **Google Auth Platform → Branding / Audience**).
2. **User type: External** → **Create**. (External is correct even for personal
   use; "Internal" only exists for Google Workspace orgs.)
3. Fill the required fields:
   - **App name**: e.g. `Pantria`
   - **User support email**: your email
   - **Developer contact email**: your email
   - (Logo, domains, etc. are optional and can stay blank.)
4. **Scopes** step → **Add or remove scopes** → add:
   ```
   https://www.googleapis.com/auth/calendar
   ```
   (Full read/write calendar access — Pantria needs to create, update and delete
   events.) Save and continue.
5. **Publishing status** — this matters for how long a connection lasts:
   - **Recommended: "Publish app" → In production.** Because `…/auth/calendar`
     is a *sensitive* scope, an unverified production app shows a one-time
     **"Google hasn't verified this app"** warning at connect — click
     **Advanced → Go to Pantria (unsafe)** to proceed. This is fine for your own
     household. Benefit: the login (refresh token) **does not expire**.
   - **Alternative: leave it in "Testing".** Then add every household member
     under **Test users** (up to 100). No warning screen, but Google **expires
     the refresh token after 7 days**, so you'd have to reconnect weekly.
   > You do **not** need Google's full app verification unless you want to remove
   > the warning screen or serve >100 users.

## 4. Create the OAuth client ID

1. **APIs & Services → Credentials** (newer: **Google Auth Platform → Clients**).
2. **+ Create credentials → OAuth client ID**.
3. **Application type: Web application.**
4. **Name**: e.g. `Pantria web`.
5. **Authorized redirect URIs → + Add URI** → paste your redirect URI from
   "Before you start", **exactly**, e.g.
   `http://localhost:3001/calendar_connection/callback`.
   - (You can add several — e.g. both your localhost preview and your real
     https host — so the same client works in both.)
   - "Authorized JavaScript origins" can be left empty (Pantria uses the
     server-side flow).
6. **Create**. Google shows your **Client ID** and **Client secret** — keep this
   dialog open (or you can re-open the client later to copy them).

## 5. Connect in Pantria

1. **Calendar → Calendar sync** (admin only).
2. Paste the **Client ID** and **Client secret** → **Save**. (The secret is
   stored encrypted and never shown again.)
3. Click **Connect Google Calendar** → Google consent (click through the
   "unverified app" warning if you chose production) → you're returned to
   Pantria, now **Connected**.
4. **Choose which calendar** to sync from the picker → **Save**.
5. Done. Pantria pulls changes every ~5 minutes (or click **Sync now**) and
   pushes your local edits immediately.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| **`redirect_uri_mismatch`** at Google | The redirect URI in the client must match Pantria's **exactly** (scheme, host, port, path, no trailing slash). Copy it from the settings page. |
| **405 after consent** | You registered the `/calendar_connection/**connect**` path instead of `/calendar_connection/**callback**`. Use the callback path. |
| **"Access blocked: app not verified"** with no "Advanced" link | The signing-in account isn't allowed. In **Testing** mode, add it under **Test users**; or publish the app **In production** (then "Advanced → Go to … (unsafe)" appears). |
| **Disconnects after ~7 days** | The app is in **Testing** publishing status (refresh tokens expire in 7 days). Publish it **In production** for long-lived access. |
| **`invalid_client`** | Wrong Client ID/secret, or the secret was rotated in Google. Re-copy both into the settings page and save. |
| **Nothing syncs after connecting** | Make sure you picked a calendar in the picker, and that the worker process is running (Solid Queue drives the 5-min poll). Use **Sync now** to trigger immediately. |

> **Note on credentials & rotation:** Pantria encrypts the client secret and the
> OAuth tokens at rest (derived from `SECRET_KEY_BASE`). If you rotate
> `SECRET_KEY_BASE`, stored secrets become unreadable — just reconnect.
