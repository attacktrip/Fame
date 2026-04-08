-- ============================================================
-- Fame Client — Supabase Setup
-- Запусти в Supabase → SQL Editor → New query → Run
-- ============================================================

-- 1. Таблица профилей
CREATE TABLE IF NOT EXISTS public.profiles (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id       UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE NOT NULL,
  nickname      TEXT NOT NULL DEFAULT 'Player',
  email         TEXT,
  plan          TEXT NOT NULL DEFAULT 'none',
  hwid          TEXT,
  hwid_reset_at TIMESTAMPTZ,
  sub_expires   TIMESTAMPTZ,
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Индексы
CREATE INDEX IF NOT EXISTS profiles_user_id_idx ON public.profiles(user_id);
CREATE INDEX IF NOT EXISTS profiles_hwid_idx    ON public.profiles(hwid);
CREATE INDEX IF NOT EXISTS profiles_email_idx   ON public.profiles(email);

-- 3. RLS — включить
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 4. Политики RLS
DROP POLICY IF EXISTS "select_own" ON public.profiles;
DROP POLICY IF EXISTS "insert_own" ON public.profiles;
DROP POLICY IF EXISTS "update_own" ON public.profiles;

CREATE POLICY "select_own" ON public.profiles
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "insert_own" ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "update_own" ON public.profiles
  FOR UPDATE USING (auth.uid() = user_id);

-- 5. Функция проверки подписки (вызывается лаунчером)
CREATE OR REPLACE FUNCTION public.check_subscription(p_user_id UUID, p_hwid TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec public.profiles%ROWTYPE;
  is_active BOOLEAN;
BEGIN
  SELECT * INTO rec FROM public.profiles WHERE user_id = p_user_id;

  IF NOT FOUND THEN
    RETURN json_build_object('valid', false, 'reason', 'user_not_found');
  END IF;

  -- Привязать HWID если ещё не привязан
  IF rec.hwid IS NULL THEN
    UPDATE public.profiles SET hwid = p_hwid WHERE user_id = p_user_id;
    rec.hwid := p_hwid;
  END IF;

  -- Проверить HWID
  IF rec.hwid != p_hwid THEN
    RETURN json_build_object('valid', false, 'reason', 'hwid_mismatch');
  END IF;

  -- Проверить подписку
  is_active := rec.plan = 'lifetime'
    OR (rec.plan != 'none' AND rec.sub_expires IS NOT NULL AND rec.sub_expires > NOW());

  IF NOT is_active THEN
    RETURN json_build_object('valid', false, 'reason', 'no_subscription', 'plan', rec.plan);
  END IF;

  RETURN json_build_object(
    'valid',    true,
    'plan',     rec.plan,
    'expires',  rec.sub_expires,
    'nickname', rec.nickname
  );
END;
$$;

-- 7. Разрешить вызов функции авторизованным пользователям
GRANT EXECUTE ON FUNCTION public.check_subscription(UUID, TEXT) TO authenticated;

-- ============================================================
-- ВАЖНО: В Supabase → Authentication → URL Configuration
--
-- Site URL (ОДНА строка, без слэша в конце):
--   https://ТВО_НИК.github.io
--
-- Redirect URLs (добавь ВСЕ три):
--   https://ТВО_НИК.github.io/fameclient-site/
--   https://ТВО_НИК.github.io/fameclient-site/index.html
--   https://ТВО_НИК.github.io/fameclient-site/auth/confirm.html
--
-- После этого письмо с подтверждением будет редиректить на
-- index.html, который автоматически перенаправит на auth/confirm.html
-- ============================================================
