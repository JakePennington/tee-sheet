# AGENTS.md

Context for any AI assistant (or person) making changes to Tee Sheet. Setup steps for a fresh install are in `README.md`; this file describes how the live app works.

## What it is

A phone-first app for scheduling golf rounds: upcoming rounds, multiple tee times per round, each player's status (in / pending / out), a saved list of golfers (marked by whether they're in men's league with the owner, who get preference), inviting several golfers to a round at once, importing golfers from a pasted list, rearranging golfers between tee times, guests invited by other players, and a one-line invite text to copy and send to one person at a time.

- Live site: https://jakepennington.github.io/tee-sheet/
- Repo: https://github.com/JakePennington/tee-sheet (public, personal account)
- Hosting: GitHub Pages, deployed from `main` at the repo root. Pushing to `main` redeploys in about 30 seconds.
- Backend: Supabase project `https://juliermtdyeiaxtcscwr.supabase.co` (region ca-central-1).

## Files

| File | Role |
|---|---|
| `index.html` | The entire app: markup, CSS and JavaScript inline. No build step, no framework. |
| `config.js` | Supabase URL and **publishable** key. Public by design; never put the secret/service_role key here. |
| `supabase-setup.sql` | Schema and row-level security. Keep it in sync with any database change. |
| `manifest.webmanifest`, `icons/` | Home-screen name and icon (iPhone uses `icons/icon-180.png`). |

`supabase-js` loads from jsDelivr pinned to an exact version (`@supabase/supabase-js@2.117.2`, UMD build, global `supabase`).

## Data model

Two tables, `public.rounds` and `public.regulars`, with the same columns. **The UI calls regulars "Golfers"**; the table, code identifiers (`regulars`, `regularId`, `renderRegulars`) and local-storage key kept the original name to avoid a data migration.

| Column | Type | Notes |
|---|---|---|
| `id` | text, PK | Client-generated random id |
| `user_id` | uuid | Owner; defaults to `auth.uid()` |
| `data` | jsonb | The whole record (shapes below) |
| `updated_at` | timestamptz | Mirrors `data.updatedAt` |

Round `data` shape:

```json
{
  "course": "Pine Hollow Golf Club",
  "date": "2026-10-17",
  "notes": "Carts booked for both groups.",
  "example": false,
  "teeTimes": [{"id": "t1", "time": "08:10"}],
  "players": [
    {"id": "p1", "name": "Me", "regularId": "", "status": "in", "teeTimeId": "t1", "guestOf": ""},
    {"id": "p2", "name": "Dave", "regularId": "g1", "status": "pending", "teeTimeId": "t1", "guestOf": "", "note": "Needs the later tee time"}
  ],
  "createdAt": "2026-10-09T20:00:00.000Z",
  "updatedAt": "2026-10-09T20:00:00.000Z"
}
```

- `date` is a local calendar date (`YYYY-MM-DD`); `time` is 24-hour `HH:MM`.
- `status` is `in`, `pending` or `out`. Out players keep their `teeTimeId` but don't take a spot.
- Each tee time holds 4 players (`SLOTS_PER_TEE`). Overbooking is allowed and shown as a warning.
- `teeTimeId: ""` means no tee time yet. `guestOf` is another player's `id`, or `""` for the organizer's own invite.
- `note` is optional free text for that golfer on that round, shown under their name (also in Rearrange mode) and edited from the player panel.
- `regularId` links a player to a regular; older players without one are matched to a regular by name (case-insensitive).

Regular (golfer) `data` shape:

```json
{"name": "Dave", "league": true, "createdAt": "...", "updatedAt": "..."}
```

- `league` means the person is in men's league with the owner. League members get a "League" badge, sort first among players with the same status, and appear first in the Invite players checklist (then by number of rounds played, then by name).

- `normalize()` / `normalizeRegular()` in `index.html` fills defaults for missing fields, so **new fields can be added to `data` without a database migration**. Only add columns or tables when a query actually needs them.

## Security

- Row-level security: a signed-in user can read, insert, update and delete only rows where `user_id` is their own id. Signed-out requests see nothing and can't write.
- New signups are disabled. There is one user (the owner), created in the Supabase dashboard with email + password.
- Email + password is deliberate: on iPhone a home-screen app has storage separate from Safari, so magic links would sign in Safari instead of the app.

## How the app works

- **Storage modes:** if `config.js` has values, the app requires sign-in and uses Supabase (`storeMode = 'cloud'`). If both values are empty, it skips sign-in and saves to `localStorage` only (`storeMode = 'local'`), which is handy for testing without touching real data.
- **Writes** are optimistic: the UI updates immediately, then a per-record queue sends one upsert at a time. `saveDoc(table, doc)` and `deleteDoc(table, id)` work for both tables; `TABLES` maps each table to its local-storage key and normalizer. A failed write shows a toast and refetches.
- **Sync:** a Supabase Realtime subscription applies changes from other devices, and the app refetches whenever it becomes visible again. When both sides have a round, the newer `updatedAt` wins.
- **Rendering:** plain functions build HTML strings (`renderList`, `renderRound`, `sheetHtml`). All user text goes through `esc()`. Clicks are handled by one delegated listener keyed on `data-action` attributes.
- **Invite players** (`invitePlayersSheet`) lists golfers not already on the round as a multi-select checklist, plus a "Someone new" field. Invitees start as `pending`; "Next open spot" fills tee times in order with `firstOpenTee()`.
- **Import list** (`importSheet`, `parseNameList`) splits pasted text on newlines, commas and semicolons, strips bullets, numbering and checkboxes, dedupes, skips existing golfers, and previews with per-name league toggles.
- **Rearrange** mode (`arranging` state) on a round: tap a golfer, then another golfer in a different group to swap tee times, or an open spot / "No tee time" row to move them.
- **Sign out** lives only on the Golfers screen footer.
- **Edits** happen in bottom sheets (`openSheet(kind, data)`). Confirmations are inline ("Tap again to delete"), not `confirm()` dialogs.

## Conventions

- Phone first. Keep tap targets at least 44px and form inputs at 16px font size (smaller makes iOS zoom in).
- Colors are CSS custom properties on `:root`, redefined for dark mode. Never hard-code a color in a component rule.
- Fonts: Barlow Condensed for display and times, Barlow for body (Google Fonts).
- JavaScript: tabs for indentation, single quotes, no build tooling, no new dependencies unless they do substantial work.
- Commits use the GitHub noreply address `25590386+JakePennington@users.noreply.github.com`, set in this repo's local git config. Don't use a work email.

## Making changes

1. Edit `index.html` (and `supabase-setup.sql` if the database changes).
2. Test locally by opening `index.html` in a browser. With `config.js` filled in, it uses the **real** data; blank both values temporarily for a throwaway device-only copy (don't commit that).
3. Database or auth changes: run SQL in the Supabase dashboard's SQL editor, or use a Supabase personal access token with the Management API. No token is kept around; create one when needed and revoke it after.
4. Commit and push to `main`. Pages redeploys automatically. On open and whenever it returns to the foreground, the app compares the server's `Last-Modified` for the page with `document.lastModified` and reloads once if the page is newer (`reloadIfUpdated()`), so phones pick up deploys without being force-closed.

Free Supabase projects pause after about a week without use. Data is kept; restore the project from the dashboard.
