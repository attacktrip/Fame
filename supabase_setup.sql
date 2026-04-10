-- ============================================================
-- Fame Client — Supabase Setup
-- Запусти ВСЁ это в Supabase SQL Editor
-- ============================================================

-- 1. PROFILES TABLE
create table if not exists public.profiles (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  email      text,
  nickname   text,
  hwid       text,
  created_at timestamptz default now()
);

alter table public.profiles enable row level security;

-- Удаляем старые политики если есть
drop policy if exists "profiles_select_own" on public.profiles;
drop policy if exists "profiles_insert_own" on public.profiles;
drop policy if exists "profiles_update_own" on public.profiles;
drop policy if exists "profiles_select_all" on public.profiles;

-- Пользователь может читать/обновлять свой профиль
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = user_id);

create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = user_id);

create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = user_id);

-- Все могут читать (для admin panel)
create policy "profiles_select_all" on public.profiles
  for select using (true);

-- Все могут обновлять (для admin panel — сброс HWID)
create policy "profiles_update_all" on public.profiles
  for update using (true);


-- 2. SUBSCRIPTIONS TABLE
create table if not exists public.subscriptions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade,
  user_email  text,
  plan        text not null,
  expires_at  timestamptz,
  created_at  timestamptz default now()
);

alter table public.subscriptions enable row level security;

drop policy if exists "subs_select_own" on public.subscriptions;
drop policy if exists "subs_select_all" on public.subscriptions;
drop policy if exists "subs_insert_admin" on public.subscriptions;
drop policy if exists "subs_update_admin" on public.subscriptions;
drop policy if exists "subs_delete_admin" on public.subscriptions;

-- Все могут читать, вставлять, обновлять, удалять (admin panel + launcher)
create policy "subs_all" on public.subscriptions
  for all using (true) with check (true);


-- 3. RPC: check_subscription
create or replace function public.check_subscription(
  p_user_id uuid,
  p_hwid    text
)
returns json
language plpgsql
security definer
as $$
declare
  v_profile  public.profiles%rowtype;
  v_plans    text[];
  v_now      timestamptz := now();
begin
  select * into v_profile from public.profiles where user_id = p_user_id;

  if not found then
    insert into public.profiles(user_id, hwid) values(p_user_id, p_hwid)
    on conflict(user_id) do nothing;
    return json_build_object('valid', true, 'plans', '{}', 'reason', 'new_user');
  end if;

  if v_profile.hwid is not null and v_profile.hwid != '' and v_profile.hwid != p_hwid then
    return json_build_object('valid', false, 'plans', '{}', 'reason', 'hwid_mismatch');
  end if;

  if v_profile.hwid is null or v_profile.hwid = '' then
    update public.profiles set hwid = p_hwid where user_id = p_user_id;
  end if;

  select array_agg(plan) into v_plans
  from public.subscriptions
  where user_id = p_user_id
    and (expires_at is null or expires_at > v_now);

  if v_plans is null or array_length(v_plans, 1) is null then
    return json_build_object('valid', false, 'plans', '{}', 'reason', 'no_subscription');
  end if;

  return json_build_object('valid', true, 'plans', v_plans, 'reason', 'ok');
end;
$$;

grant execute on function public.check_subscription(uuid, text) to anon, authenticated;

-- 4. Indexes
create index if not exists idx_subs_user_id on public.subscriptions(user_id);
create index if not exists idx_subs_email on public.subscriptions(user_email);
create index if not exists idx_profiles_email on public.profiles(email);

-- ============================================================
-- ГОТОВО. Теперь:
-- 1. Замени ADMIN_EMAILS в admin.html и dashboard.html
-- 2. Создай аккаунт в Supabase Auth → Authentication → Users
-- 3. Загрузи сайт на Netlify
-- ============================================================
