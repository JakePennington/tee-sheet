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
