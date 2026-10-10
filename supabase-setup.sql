-- Run once in the Supabase SQL editor.

create table if not exists public.rounds (
	id text primary key,
	user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
	data jsonb not null,
	updated_at timestamptz not null default now()
);

create index if not exists rounds_user_id_idx on public.rounds (user_id);

alter table public.rounds enable row level security;

create policy "Read own rounds" on public.rounds
	for select to authenticated
	using (user_id = (select auth.uid()));

create policy "Create own rounds" on public.rounds
	for insert to authenticated
	with check (user_id = (select auth.uid()));

create policy "Update own rounds" on public.rounds
	for update to authenticated
	using (user_id = (select auth.uid()))
	with check (user_id = (select auth.uid()));

create policy "Delete own rounds" on public.rounds
	for delete to authenticated
	using (user_id = (select auth.uid()));

-- Live sync between your phone and laptop.
alter publication supabase_realtime add table public.rounds;

-- Regulars: people you play with often, and whether they're in men's league.
create table if not exists public.regulars (
	id text primary key,
	user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
	data jsonb not null,
	updated_at timestamptz not null default now()
);

create index if not exists regulars_user_id_idx on public.regulars (user_id);

alter table public.regulars enable row level security;

create policy "Read own regulars" on public.regulars
	for select to authenticated
	using (user_id = (select auth.uid()));

create policy "Create own regulars" on public.regulars
	for insert to authenticated
	with check (user_id = (select auth.uid()));

create policy "Update own regulars" on public.regulars
	for update to authenticated
	using (user_id = (select auth.uid()))
	with check (user_id = (select auth.uid()));

create policy "Delete own regulars" on public.regulars
	for delete to authenticated
	using (user_id = (select auth.uid()));

alter publication supabase_realtime add table public.regulars;

-- Shared round links: returns the public view of one round for its share token, so golfers
-- who aren't signed in can see it. Only what's safe to show; nothing else is readable anonymously.
create or replace function public.shared_round(token text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
	select jsonb_build_object(
		'course', r.data->>'course',
		'date', r.data->>'date',
		'holes', coalesce((r.data->>'holes')::int, 18),
		'notes', coalesce(r.data->>'notes', ''),
		'tentative', coalesce((r.data->>'tentative')::boolean, false),
		'bookOn', coalesce(r.data->>'bookOn', ''),
		'teeTimes', coalesce(r.data->'teeTimes', '[]'::jsonb),
		'players', coalesce((
			select jsonb_agg(jsonb_build_object(
				'id', p->>'id',
				'name', coalesce(g.data->>'name', p->>'name'),
				'status', p->>'status',
				'teeTimeId', coalesce(p->>'teeTimeId', '')
			))
			from jsonb_array_elements(coalesce(r.data->'players', '[]'::jsonb)) p
			left join public.regulars g on g.id = p->>'regularId' and g.user_id = r.user_id
			where p->>'status' in ('in', 'pending')
		), '[]'::jsonb)
	)
	from public.rounds r
	where length(token) >= 20 and r.data->>'shareToken' = token
	limit 1;
$$;

revoke all on function public.shared_round(text) from public;
grant execute on function public.shared_round(text) to anon, authenticated;
