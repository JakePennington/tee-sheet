# AGENTS.md

Context for any AI assistant (or person) making changes to Tee Sheet. Setup steps for a fresh install are in `README.md`; this file describes how the live app works.

## What it is

A phone-first app for scheduling golf rounds: upcoming rounds, multiple tee times per round, each player's status (in / pending / out), a saved list of golfers (ranked by how often they accept, and marked by whether they're in men's league with the owner), inviting several golfers to a round at once, dragging golfers between tee times, and a one-line invite text to copy and send to one person at a time.

- Live site: https://jakepennington.github.io/tee-sheet/
- Repo: https://github.com/JakePennington/tee-sheet (public, personal account)
- Hosting: GitHub Pages, deployed from `main` at the repo root. Pushing to `main` redeploys in about 30 seconds.
- Backend: Supabase project `https://juliermtdyeiaxtcscwr.supabase.co` (region ca-central-1).

## Files

| File | Role |
|---|---|
| `index.html` | The entire app: markup, CSS and JavaScript inline. No build step, no framework. |
| `config.js` | Supabase URL, **publishable** key, and `ownerName` (the owner's name as a player; defaults to "Me"). Public by design; never put the secret/service_role key here. |
| `sw.js` | Service worker: network-first for page loads so the home-screen app gets new deploys, with the last copy cached for offline. |
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
  "tentative": true,
  "bookOn": "2026-10-10",
  "teeTimes": [{"id": "t1", "time": "08:10", "spots": 4}],
  "players": [
    {"id": "p1", "name": "Jake Pennington", "regularId": "", "status": "in", "teeTimeId": "t1"},
    {"id": "p2", "name": "Dave", "regularId": "g1", "status": "pending", "teeTimeId": "t1", "note": "Needs the later tee time"}
  ],
  "createdAt": "2026-10-09T20:00:00.000Z",
  "updatedAt": "2026-10-09T20:00:00.000Z"
}
```

- `tentative: true` means the tee times aren't booked yet (gauging interest). `bookOn` is an optional date when the tee times open for booking (cleared when booked). On the home screen a tentative round's card is amber with a dashed border and a "Tentative · Book Oct 10" / "Tentative · Book now" label (solid border once due), and a booking card with a "Mark booked" button on the round, and the invite text asks "you interested?" instead of "you in?". Missing means booked.
- `date` is a local calendar date (`YYYY-MM-DD`); `time` is 24-hour `HH:MM`.
- `status` is `in`, `pending` or `out`. **Only In players are in tee times.** Pending players show under "Waiting to hear back" and Out under "Can't make it". Status changes (the status pill or the player panel) go through `setStatus()`, which never assigns a tee time: it clears `teeTimeId`, so a newly-In golfer lands in "No tee time yet" until dragged. Older rounds may have pending players with a `teeTimeId`; it's ignored for display and capacity.
- Each tee time holds `spots` In players (1–4, the number booked; defaults to `MAX_SPOTS` = 4 when missing), set in the New round form or by tapping the tee header; open spots count only In players. Overbooking is allowed and shown as a warning.
- `teeTimeId: ""` means no tee time yet. After a golfer is In, their tee time changes only by dragging on the round page.
- Older rounds may have a `guestOf` field from a removed guest feature; it's ignored.
- New rounds always start with the owner (`ownerName`) as In on the first tee time; there's no "I'm playing" option. The owner removes themselves from the round if they won't play.
- Players saved with the old name `"Me"` are shown as `ownerName` by `normalize()` and saved with it on the next edit.
- Pending means the owner has already texted the golfer (they text right after inviting), so the app doesn't track texting separately.
- `note` is optional free text for that golfer on that round, shown under their name and edited from the player panel.
- `regularId` links a player to a regular; older players without one are matched to a regular by name (case-insensitive).

Regular (golfer) `data` shape:

```json
{"name": "Dave", "league": true, "note": "Out until November", "createdAt": "...", "updatedAt": "..."}
```

- `note` on a golfer follows them everywhere (⚑, on rounds, the invite checklist and the Golfers screen). It's edited on the Golfers screen or from a golfer's panel on a round. The per-round player `note` (✎) is separate.
- `league` means the person is in men's league with the owner. League members get a "League" badge and sort first among players with the same status on a round.

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
- **Ranking** (`golferStats`, `rankedRegulars`): golfers are ordered by how many rounds they were **In** for (accepted), then by their most recent such round, then by name. The owner gives preference to golfers who play often and recently.
- **Invite players** (`invitePlayersSheet`) lists golfers not already on the round as a ranked multi-select checklist. "Someone not in your golfers?" reveals a name field with Save to golfers / men's league options (shown up front only when no golfers are left). Invitees start as `pending` with no tee time, then the panel becomes **Text your invites** (`sendInvitesSheet`): an editable message and a Text button per invitee.
- **Drag and drop** on a round: every golfer has a grip, and every section is a drop zone with `data-drop-status` (plus `data-drop-tee` for In sections). Dropping onto a tee time makes them In there; onto No tee time yet makes them In with no tee time; onto Waiting to hear back makes them Pending; onto Can't make it makes them Out. Dropping onto a golfer in a tee time swaps (the dragged golfer becomes In there; the displaced golfer gets the dragged golfer's old tee time if they had one, otherwise No tee time yet). Empty sections render as `dropZone()` placeholders that only show while dragging. Dragging uses pointer events with `touch-action: none` on the grip only, so the page still scrolls normally; `render()` is skipped mid-drag.
- **Updates:** `sw.js` serves page loads network-first. `reloadIfUpdated()` also fetches the page on open and whenever the app returns to the foreground, and reloads if the HTML changed since launch.
- **Texting** (`openMessages`) opens a new Messages compose with the invite filled in via `sms:&body=` (`?body=` on non-Apple devices); the owner picks the recipient in Messages, and no phone numbers are stored. The iOS share sheet was tried first and didn't offer Messages from the home-screen app. Text buttons appear only in the post-invite list (with a session-only ✓ Texted marker) and as Text it in the Invite text panel.
- **Tee times on the round page:** tee times are entered in the New round form, but after that they're managed only on the round page (Edit round has no tee times). Tapping a tee header's time opens `teeSheet` to change the time and players booked. "+ Add tee time" adds one 10 minutes after the last (or 8:00 AM) with 4 spots and saves immediately. Each tee header has a × that arms on the first tap (`armedTee`, shows "Remove?") and removes on the second; any other click or 4 seconds disarms. Removing a tee time moves its In golfers to No tee time yet.
- **Keyboard:** `fitSheet()` sizes the bottom-sheet wrapper to `visualViewport` so sheets sit above the on-screen keyboard (search results and sticky buttons stay visible). 
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
4. Commit and push to `main`. Pages redeploys automatically, and phones pick up the new version on their next open or return to the app (see **Updates** above).

Free Supabase projects pause after about a week without use. Data is kept; restore the project from the dashboard.
