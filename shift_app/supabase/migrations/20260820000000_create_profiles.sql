create schema if not exists private;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  name text not null,
  privacy_consent boolean not null default false,
  ai_consent boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

grant select, insert, update on public.profiles to authenticated;
alter table public.profiles enable row level security;

create policy "Users can read their own profile"
on public.profiles for select to authenticated
using ((select auth.uid()) = id);

create policy "Users can insert their own profile"
on public.profiles for insert to authenticated
with check ((select auth.uid()) = id);

create policy "Users can update their own profile"
on public.profiles for update to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create or replace function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, name, privacy_consent, ai_consent)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'name', '사용자'),
    coalesce((new.raw_user_meta_data ->> 'privacy_consent')::boolean, false),
    coalesce((new.raw_user_meta_data ->> 'ai_consent')::boolean, false)
  )
  on conflict (id) do update set
    email = excluded.email,
    name = excluded.name,
    privacy_consent = excluded.privacy_consent,
    ai_consent = excluded.ai_consent,
    updated_at = now();
  return new;
end;
$$;

revoke all on function private.handle_new_user() from public;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure private.handle_new_user();
