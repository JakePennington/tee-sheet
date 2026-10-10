# Tee Sheet

A phone-first app for planning golf rounds: tee times (9 or 18 holes), who's in, who you're waiting to hear back from, and who can't make it, plus a ranked list of the golfers you play with and read-only links to share a round with golfers who aren't signed in. Data syncs between devices through Supabase; the site is static, so it hosts free on GitHub Pages. See `AGENTS.md` for how the app works.

## Files

| File | What it is |
|---|---|
| `index.html` | The whole app |
| `config.js` | Your Supabase URL, publishable key, and your name as it appears on rounds |
| `sw.js` | Service worker: loads new versions quickly and lets the app open offline |
| `supabase-setup.sql` | Creates the `rounds` and `regulars` (golfers) tables, locks them to your account, and adds the `shared_round` function for share links |
| `.github/workflows/keep-supabase-awake.yml` | Pings Supabase twice a week so the free project doesn't pause |
| `manifest.webmanifest`, `icons/` | Home-screen name and icon |
| `AGENTS.md` | How the app works, for whoever (or whichever AI) changes it next |

## Setup (about 10 minutes)

### 1. Supabase (free)

1. Create a project at [supabase.com](https://supabase.com).
2. **SQL Editor** → paste `supabase-setup.sql` → **Run**.
3. **Authentication → Users → Add user → Create new user**. Enter your email and a password, and tick **Auto Confirm User**.
4. **Authentication → Sign In / Providers**: turn off **Allow new users to sign up**. You're the only account.
5. **Project Settings → API Keys**: copy the **Project URL** and the **publishable** (or legacy **anon**) key into `config.js`, and set `ownerName`.

The publishable key is meant to be public. Row-level security means it can only read or write data belonging to the signed-in user. Never put the **secret** / **service_role** key in `config.js`.

### 2. GitHub Pages (free)

```bash
cd ~/repos/tee-sheet
git init -b main
git config user.email "you@personal.example"   # your personal email, not work
git add .
git commit -m "Tee Sheet"
git remote add origin git@github.com:<you>/tee-sheet.git
git push -u origin main
```

Then in the repo on GitHub: **Settings → Pages → Deploy from a branch → `main` / root**. The site appears at `https://<you>.github.io/tee-sheet/` within a minute or two.

### 3. Phone

Open the URL in Safari (iPhone) or Chrome (Android), sign in, then **Share → Add to Home Screen**. It opens full-screen like an app and stays signed in.

## Good to know

- **Keeping Supabase awake:** free projects pause after about a week without use. The keep-awake workflow prevents that. GitHub turns off scheduled workflows in repos with no commits for 60 days; if that happens, re-enable it under the repo's **Actions** tab. If the project does pause, the app says it can't reach your tee sheet; restore the project from the Supabase dashboard.
- **Offline:** after the first visit the app opens without signal, showing your last synced copy. Changes made offline are saved on the phone and sync when you're back online.
- **Trying it locally:** open `index.html` directly with `config.js`'s keys blanked and it runs in device-only test mode with no sign-in, saving to that browser.
- **Updating:** edit, commit, push. GitHub Pages redeploys automatically, and the app picks up the new version the next time you open it.
