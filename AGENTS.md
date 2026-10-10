# AGENTS.md

Context for any AI assistant (or person) making changes to Tee Sheet. Setup steps for a fresh install are in `README.md`; this file describes how the live app works.

## What it is

A phone-first app for planning golf rounds: upcoming rounds (9 or 18 holes, booked or tentative), multiple tee times per round with a set number of spots, each golfer's status (in / pending / out), a saved list of golfers (ranked by how often they've played, and marked by whether they're in men's league with the owner), inviting several golfers at once and texting them, and arranging golfers by drag and drop.

- Live site: https://jakepennington.github.io/tee-sheet/
- Repo: https://github.com/JakePennington/tee-sheet (public, personal account)
- Hosting: GitHub Pages, deployed from `main` at the repo root. Pushing to `main` redeploys in about 30 seconds.
- Backend: Supabase project `https://juliermtdyeiaxtcscwr.supabase.co` (region ca-central-1).

## Files

| File | Role |
|---|---|
| `index.html` | The entire app: markup, CSS and JavaScript inline. No build step, no framework. |
| `config.js` | Supabase URL, **publishable** key, and `ownerName` (the owner's name as a player; defaults to "Me"). Public by design; never put the secret/service_role key here. |
| `sw.js` | Service worker: network-first for page loads and `config.js`; cache-first for the pinned supabase-js build and Google Fonts, so the app opens offline. |
| `supabase-setup.sql` | Schema and row-level security. Keep it in sync with any database change. |
| `.github/workflows/keep-supabase-awake.yml` | Twice-weekly ping so the free Supabase project doesn't pause. |
| `manifest.webmanifest`, `icons/` | Home-screen name and icon (iPhone uses `icons/icon-180.png`). |

`supabase-js` loads from jsDelivr pinned to an exact version (`@supabase/supabase-js@2.117.2`, UMD build, global `supabase`).

## Data model

Two tables, `public.rounds` and `public.regulars`, with the same columns. **The UI calls regulars "Golfers"**; the table, code identifiers (`regulars`, `regularId`, `renderRegulars`) and local-storage key kept the original name to avoid a data migration.

| Column | Type | Notes |
|---|---|---|
| `id` | text, PK | Client-generated random id |
| `user_id` | uuid | Owner; defaults to `auth.uid()` |
| `data` | jsonb | The whole record (shapes below) |
| `updated_at` | timestamptz | Set on every write; used as the version for conflict checks |

Round `data` shape:

```json
{
  "course": "Pine Hollow Golf Club",
  "date": "2026-10-17",
  "holes": 18,
  "notes": "Carts booked for both groups.",
  "tentative": true,
  "bookOn": "2026-10-10",
  "teeTimes": [{"id": "t1", "time": "08:10", "spots": 4}],
  "players": [
    {"id": "p1", "name": "Jake Pennington", "regularId": "", "status": "in", "teeTimeId": "t1"},
    {"id": "p2", "name": "Dave", "regularId": "g1", "status": "pending", "teeTimeId": "", "note": "Needs the later tee time"}
  ],
  "createdAt": "2026-10-09T20:00:00.000Z",
  "updatedAt": "2026-10-09T20:00:00.000Z"
}
```

- `holes` is 18 or 9 (missing means 18). Shown on the home card and round page, and used in the invite text ("Playing 9 holes at …").
- `tentative: true` means the tee times aren't booked yet (gauging interest). `bookOn` is an optional date when the tee times open for booking (cleared when booked). A tentative round's home card is amber with a dashed border and a "Tentative · Book Oct 10" / "Tentative · Book now" label; the round page shows a booking card with "Mark booked"; the invite text asks "you interested?" instead of "you in?".
- `date` is a local calendar date (`YYYY-MM-DD`); `time` is 24-hour `HH:MM`.
- `status` is `in`, `pending` or `out`. **Only In players are in tee times.** Pending players show under "Waiting to hear back" and Out under "Can't make it". Pending means the owner has already texted them. Status changes from the status pill or player panel go through `setStatus()`, which clears `teeTimeId`, so a newly-In golfer lands in "No tee time yet" until placed.
- Each tee time holds `spots` In players (1–4, the number booked; defaults to `MAX_SPOTS` = 4). Open spots count only In players. Overbooking is allowed and shown as a warning.
- `regularId` links a player to a golfer. On rounds the golfer's **current** name is shown (`displayName()`); `name` is a fallback snapshot. Players without a `regularId` (the owner, or very old data) are matched to golfers by name.
- `note` is optional free text for that golfer on that round.
- New rounds always start with the owner (`ownerName`) as In on the first tee time. Players saved with the old name `"Me"` are shown as `ownerName`.
- Older rounds may contain `guestOf`, `textedAt` or `example` fields from removed features; they're ignored.

Regular (golfer) `data` shape:

```json
{"name": "Dave", "league": true, "note": "Out until November", "archived": false, "createdAt": "...", "updatedAt": "..."}
```

- `archived: true` is set by "Remove from golfers" instead of deleting, so past rounds keep the golfer's link, badge and note. Archived golfers are hidden from the Golfers list and invite panel (`activeRegulars()`), listed in a collapsed Archived section with Restore, and restored automatically if invited or added again by name.
- `note` follows the golfer everywhere (⚑). The per-round player `note` (✎) is separate.
- `league`: in men's league with the owner. League members get a "League" badge and sort first among players with the same status on a round.

`normalize()` / `normalizeRegular()` fill defaults for missing fields, so **new fields can be added to `data` without a database migration**.

## Security

- Row-level security: a signed-in user can read, insert, update and delete only rows where `user_id` is their own id. Signed-out requests see nothing and can't write.
- New signups are disabled. There is one user (the owner), created in the Supabase dashboard with email + password.
- Email + password is deliberate: on iPhone a home-screen app has storage separate from Safari, so magic links would sign in Safari instead of the app.

## How the app works

### Storage and sync

- **Modes:** if `config.js` has keys, the app requires sign-in and uses Supabase (`storeMode = 'cloud'`). If the keys are blank it runs in device-only test mode (`'local'`). If the keys are set but supabase-js didn't load, it shows "Can't reach your tee sheet" (`'unreachable'`); it never silently falls back to device-only.
- **Writes** are optimistic. `saveDoc(table, doc)` / `deleteDoc(table, id)` update the screen, then queue a job in `pending`, which is persisted to localStorage (`teesheet.pending.v1`) so unsent changes survive restarts. `flush()` sends jobs in order: inserts for new docs, and updates conditioned on `updated_at` equal to the last value seen from the server (`serverAt`). If the row changed elsewhere, the update matches nothing, and the app takes the server copy and says so (`takeServerCopy`). Network failures leave the job queued; it retries on foreground, the `online` event, pull-to-refresh, and every 30 seconds. A "N changes not synced yet · Retry" bar shows while it's failing.
- **Reads:** the last synced data is cached in localStorage (`teesheet.cache.v1`) and shown immediately on launch, then `fetchAll()` replaces it with the server copy, keeping any pending local edits on top. If the fetch fails with a cache it shows "Offline. Showing your saved copy."; with no cache it shows the can't-reach screen (which mentions a paused Supabase project) with Try again, and editing is disabled until data loads.
- **Realtime** changes from other devices apply immediately unless that record has a pending local edit.

### Screens and interactions

- **Rendering:** plain functions build HTML strings (`renderList`, `renderRound`, `renderRegulars`, `sheetHtml`). All user text goes through `esc()`. Clicks are handled by one delegated listener keyed on `data-action`. Edits happen in bottom sheets (`openSheet(kind, data)`); confirmations are inline ("Tap again to…"), not `confirm()` dialogs.
- **Ranking** (`golferStats`, `rankedRegulars(stats)`): golfers ordered by how many **past** rounds they were In for, then most recent, then name. Shown as "5 rounds · last Oct 3".
- **Invite golfers** (`invitePlayersSheet`, bottom bar button): a ranked checklist of golfers not on the round. The list order never changes while open; picks appear as removable chips in a Selected strip above it. Picking from a search clears the search and puts the cursor back in it. "+ New golfer" at the top reveals a name field; new names are always saved to Golfers (not league), and existing or archived names link to that golfer. The button is disabled until something is picked. Invitees become Pending, then the sheet becomes **Text your invites** (`sendInvitesSheet`) with an editable message and a Text button per golfer.
- **Add from an open spot** (`add-golfers`, same sheet with `addTo` set): golfers are added as **In** directly into that tee time (extras beyond its spots go to No tee time yet). The list also includes golfers already Waiting or Out, so they can be confirmed. No text step.
- **Texting** (`openMessages`) opens a new Messages compose with the invite filled in via `sms:&body=` (`?body=` on non-Apple devices); the owner picks the recipient. The iOS share sheet was tried and didn't offer Messages from the home-screen app. Invite text: `Playing 18 holes at <course> on <Sat, Oct 17> at <time>, you in?`, using the earliest tee time with room.
- **Drag and drop**: every golfer has a grip. Every section is a drop zone with `data-drop-status` (plus `data-drop-tee` for In sections): tee time = In there, No tee time yet = In, Waiting to hear back = Pending, Can't make it = Out. Dropping on a golfer in a tee time swaps. Empty sections appear as drop zones (`dropZone()`) only while dragging. Pointer events with `touch-action: none` on the grip only; `render()` is skipped mid-drag. Moves share `moveGolfer()`.
- **Long-press** a golfer (or right-click on desktop) opens a Move sheet (`moveSheet`) listing every tee time and section, as a non-drag alternative.
- **Tee times on the round page:** entered in the New round form, then managed only on the round page. Tapping a tee header's time opens `teeSheet` (time and golfers booked). "+ Add tee time" adds one 10 minutes after the last (capped at 11:59 PM) with 4 spots. The header × arms on the first tap (`armedTee`) and removes on the second.
- **Times** use `timeField()`: a list of 10-minute steps from 5:00 AM to 8:00 PM plus "Type a time…", parsed by `parseTime()` ("8:07", "807", "8:07p", "13:40"; a bare 1–5 is read as PM). iOS ignores `step` on native time pickers, hence the custom list.
- **Swipe to close** any sheet: from its header any time, or from anywhere once it's scrolled to the top and nothing has been picked or typed (`sheet.dirty`). Past a third of its height or a quick flick closes it.
- **Pull to refresh** at the top of the home, round or golfers page (`fetchAll()`).
- **Keyboard:** `fitSheet()` sizes the sheet wrapper to `visualViewport` so sheets sit above the on-screen keyboard.
- **Golfers screen:** League and Others sections, a search box once there are more than 8, and a collapsed Archived section with Restore.
- **Sign out** is at the bottom of the home screen only.
- **Updates:** `sw.js` serves page loads network-first, and `reloadIfUpdated()` reloads if the page's HTML changed since launch (checked on open and on return to foreground).

## Conventions

- Phone first. Keep tap targets at least 44px and form inputs at 16px font size (smaller makes iOS zoom in).
- No helper or explanatory text in the UI; labels, titles and error messages only.
- Say "golfers", not "players", in anything the user sees.
- Colors are CSS custom properties on `:root`, redefined for dark mode. Never hard-code a color in a component rule.
- Fonts: Barlow Condensed for display and times, Barlow for body (Google Fonts).
- JavaScript: tabs for indentation, single quotes, no build tooling, no new dependencies unless they do substantial work.
- Commits use the GitHub noreply address `25590386+JakePennington@users.noreply.github.com`, set in this repo's local git config. Don't use a work email.

## Making changes

1. Edit `index.html` (and `supabase-setup.sql` if the database changes).
2. Test locally by opening `index.html` in a browser. With `config.js` filled in, it uses the **real** data; blank the keys temporarily for a throwaway device-only copy (don't commit that).
3. Database or auth changes: run SQL in the Supabase dashboard's SQL editor, or use a Supabase personal access token with the Management API. No token is kept around; create one when needed and revoke it after.
4. Commit and push to `main`. Pages redeploys automatically, and phones pick up the new version on their next open or return to the app.
