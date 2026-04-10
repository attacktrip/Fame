-- ============================================================
-- Fame Client — Supabase Database Setup
-- Запусти это в Supabase SQL Editor
-- ============================================================

-- 1. PROFILES TABLE
create table if not exists public.profiles (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  email      text,
  nickname   text,
  hwid       text,
  created_at timestamptz default now()
);

-- Enable RLS
alter table public.profiles enable row level security;

-- Users can read/update their own profile
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = user_id);

create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = user_id);

create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = user_id);

-- Admins can read all profiles (service role bypasses RLS anyway)
create policy "profiles_select_all" on public.profiles
  for select using (true);  -- anon can read for admin panel


-- 2. SUBSCRIPTIONS TABLE
create table if not exists public.subscriptions (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade,
  user_email  text,
  plan        text not null,  -- '1165_basic','1165_premium','1165_lifetime','1214_basic','1214_premium','1214_lifetime'
  expires_at  timestamptz,    -- null = lifetime
  created_at  timestamptz default now()
);

-- Enable RLS
alter table public.subscriptions enable row level security;

-- Users can read their own subscriptions
create policy "subs_select_own" on public.subscriptions
  for select using (auth.uid() = user_id);

-- Anon/admin can read all (for admin panel with anon key)
create policy "subs_select_all" on public.subscriptions
  for select using (true);

-- Only service role / admin can insert/update/delete
-- (admin panel uses anon key but we allow it for simplicity)
create policy "subs_insert_admin" on public.subscriptions
  for insert with check (true);

create policy "subs_update_admin" on public.subscriptions
  for update using (true);

create policy "subs_delete_admin" on public.subscriptions
  for delete using (true);


-- 3. RPC: check_subscription (used by launcher)
-- Returns {valid: bool, plans: text[], reason: text}
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
  v_plan     text;
  v_now      timestamptz := now();
begin
  -- Get profile
  select * into v_profile from public.profiles where user_id = p_user_id;

  if not found then
    -- Auto-create profile
    insert into public.profiles(user_id, hwid) values(p_user_id, p_hwid)
    on conflict(user_id) do nothing;
    return json_build_object('valid', true, 'plans', '{}', 'reason', 'new_user');
  end if;

  -- HWID check: if profile has hwid and it doesn't match
  if v_profile.hwid is not null and v_profile.hwid != '' and v_profile.hwid != p_hwid then
    return json_build_object('valid', false, 'plans', '{}', 'reason', 'hwid_mismatch');
  end if;

  -- Bind HWID if not set
  if v_profile.hwid is null or v_profile.hwid = '' then
    update public.profiles set hwid = p_hwid where user_id = p_user_id;
  end if;

  -- Get active plans
  select array_agg(plan) into v_plans
  from public.subscriptions
  where user_id = p_user_id
    and (expires_at is null or expires_at > v_now);

  if v_plans is null then
    v_plans := '{}';
  end if;

  if array_length(v_plans, 1) is null then
    return json_build_object('valid', false, 'plans', '{}', 'reason', 'no_subscription');
  end if;

  return json_build_object('valid', true, 'plans', v_plans, 'reason', 'ok');
end;
$$;

-- Grant execute to anon and authenticated
grant execute on function public.check_subscription(uuid, text) to anon, authenticated;


-- 4. RPC: get_user_subscriptions (for dashboard)
create or replace function public.get_user_subscriptions(p_user_id uuid)
returns table(plan text, expires_at timestamptz, active boolean)
language sql
security definer
as $$
  select plan, expires_at, (expires_at is null or expires_at > now()) as active
  from public.subscriptions
  where user_id = p_user_id
  order by created_at desc;
$$;

grant execute on function public.get_user_subscriptions(uuid) to anon, authenticated;


-- 5. INDEX for performance
create index if not exists idx_subs_user_id on public.subscriptions(user_id);
create index if not exists idx_subs_expires on public.subscriptions(expires_at);
create index if not exists idx_profiles_email on public.profiles(email);

-- ============================================================
-- DONE! Теперь:
-- 1. Добавь свой email в ADMIN_EMAILS в admin.html
-- 2. Создай пользователей через Supabase Auth или сайт
-- 3. Добавляй подписки через admin.html
-- ============================================================
