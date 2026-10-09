# Tee Sheet

A phone-first app for upcoming golf rounds: tee times, who's in, who's pending, who's out, and guests. Data syncs between devices through Supabase; the site is static, so it hosts free on GitHub Pages.

## Files

| File | What it is |
|---|---|
| `index.html` | The whole app |
| `config.js` | Your Supabase URL and publishable key |
| `supabase-setup.sql` | Creates the `rounds` table and locks it to your account |
| `manifest.webmanifest`, `icons/` | Home-screen name and icon |

## Setup (about 10 minutes)

### 1. Supabase (free)

1. Create a project at [supabase.com](https://supabase.com).
2. **SQL Editor** → paste `supabase-setup.sql` → **Run**.
3. **Authentication → Users → Add user → Create new user**. Enter your email and a password, and tick **Auto Confirm User**.
4. **Authentication → Sign In / Providers**: turn off **Allow new users to sign up**. You're the only account.
5. **Project Settings → API Keys**: copy the **Project URL** and the **publishable** (or legacy **anon**) key into `config.js`.

The publishable key is meant to be public. Row-level security means it can only read or write rounds belonging to the signed-in user. Never put the **secret** / **service_role** key in `config.js`.

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

- **Free Supabase projects pause after about a week of no use.** Your data is kept; restore the project from the Supabase dashboard and it's back in a minute or two.
- **Trying it locally:** open `index.html` directly with `config.js` left empty and it runs in device-only mode with no sign-in, saving to that browser.
- **Updating:** edit, commit, push. GitHub Pages redeploys automatically; reopen the app on your phone to get the new version.
