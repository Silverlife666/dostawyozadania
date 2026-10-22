-- Harmonogram zadań i dostaw: uruchom jednorazowo w Supabase SQL Editor.
-- Po utworzeniu pierwszego użytkownika Auth ustaw go administratorem:
-- update public.delivery_schedule_users
-- set role = 'Administrator', active = true, permissions = array['edit_plan','manage_people','export_pdf','manage_users']
-- where id = '<UUID użytkownika z Authentication > Users>';

create table if not exists public.delivery_schedule_state (
  id smallint primary key default 1 check (id = 1),
  payload jsonb not null default '{"employees":[],"assignments":[],"lastModified":"—"}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create table if not exists public.delivery_schedule_users (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  role text not null default 'Pracownik' check (role in ('Administrator', 'Właściciel', 'Pracownik')),
  permissions text[] not null default array['read','export_pdf']::text[],
  active boolean not null default false,
  created_at timestamptz not null default now()
);

create or replace function public.create_delivery_schedule_profile()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.delivery_schedule_users (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists delivery_schedule_profile_after_auth_user on auth.users;
create trigger delivery_schedule_profile_after_auth_user
  after insert on auth.users for each row execute procedure public.create_delivery_schedule_profile();

alter table public.delivery_schedule_state enable row level security;
alter table public.delivery_schedule_users enable row level security;

create or replace function public.schedule_is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.delivery_schedule_users
    where id = auth.uid() and active and role = 'Administrator'
  );
$$;

create or replace function public.schedule_has_permission(permission_name text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.delivery_schedule_users
    where id = auth.uid() and active
      and (role = 'Administrator' or permission_name = any(permissions))
  );
$$;

drop policy if exists "schedule read" on public.delivery_schedule_state;
drop policy if exists "schedule write" on public.delivery_schedule_state;
create policy "schedule read" on public.delivery_schedule_state for select
  using (public.schedule_has_permission('read'));

create or replace function public.save_delivery_schedule(next_payload jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare old_assignment_count integer;
declare new_assignment_count integer;
begin
  if not public.schedule_has_permission('edit_plan') then
    raise exception 'Brak uprawnienia do edycji planu';
  end if;
  select coalesce(jsonb_array_length(payload -> 'assignments'), 0)
    into old_assignment_count from public.delivery_schedule_state where id = 1;
  new_assignment_count := coalesce(jsonb_array_length(next_payload -> 'assignments'), 0);
  if coalesce(old_assignment_count, 0) > 0 and new_assignment_count = 0 and not public.schedule_is_admin() then
    raise exception 'Tylko Administrator może wyczyścić plan';
  end if;
  insert into public.delivery_schedule_state (id, payload, updated_at, updated_by)
  values (1, next_payload, now(), auth.uid())
  on conflict (id) do update set payload = excluded.payload, updated_at = excluded.updated_at, updated_by = excluded.updated_by;
end;
$$;

revoke all on function public.save_delivery_schedule(jsonb) from public;
grant execute on function public.save_delivery_schedule(jsonb) to authenticated;

drop policy if exists "profile read" on public.delivery_schedule_users;
drop policy if exists "profile admin update" on public.delivery_schedule_users;
create policy "profile read" on public.delivery_schedule_users for select
  using (id = auth.uid() or public.schedule_is_admin());
create policy "profile admin update" on public.delivery_schedule_users for update
  using (public.schedule_is_admin()) with check (public.schedule_is_admin());

-- Konta dodawaj w Authentication > Users (e-mail jako login, PIN jako hasło).
-- Trigger utworzy nieaktywny profil Pracownika; administrator w aplikacji
-- aktywuje konto i przydzieli mu rolę/uprawnienia. Dla pierwszego konta ustaw
-- active = true razem z rolą Administrator w poleceniu z początku pliku.
