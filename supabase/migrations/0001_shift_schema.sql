-- SHIFT 앱 서버 스키마 (초안 — 리뷰 대상).
--
-- 근거: docs/SHIFT_프론트엔드_구현체크리스트.md §5의 Drift 7테이블 초안을
-- 로컬(Drift/SQLite)이 아니라 Supabase Postgres 기준으로 옮긴 것.
--
-- 원안과 달라진 점:
--   - `user_profile.password_hash`/`email` 제거 — Supabase Auth(auth.users)가
--     인증을 전담하므로 각 테이블의 user_id는 auth.users(id)를 참조한다.
--     원안 문서가 지적한 "AppState가 평문 비번을 들고 있다"는 문제는 이
--     전환으로 자연히 해소된다 — 앱은 이제 supabase.auth로만 로그인한다.
--   - `chronotype`/`caffeine_cutoff`는 아직 flutter_engine의 UserProfile에
--     대응 필드가 없어(체크리스트 §6 "결정 필요") 포함하지 않았다. 필요해지면
--     별도 마이그레이션으로 추가할 것.
--
-- 적용 방법: Supabase 대시보드 SQL Editor에 붙여넣거나,
--   `supabase db push`(CLI, 프로젝트 링크 필요)로 적용.

-- ── 1. user_profile — 계정당 1행, id는 auth.users.id와 동일 ──────────────
create table public.user_profile (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null,
  shift_timings jsonb not null default '{}'::jsonb,
  workplace_lighting text not null default 'normal'
    check (workplace_lighting in ('bright', 'normal', 'dim')),
  bedroom_lighting text not null default 'curtain'
    check (bedroom_lighting in ('blackout', 'curtain', 'none')),
  commute_minutes double precision not null default 20,
  latitude double precision not null default 35.87,
  longitude double precision not null default 128.60,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_profile enable row level security;

create policy "user_profile: 본인만 조회" on public.user_profile
  for select using (id = auth.uid());
create policy "user_profile: 본인만 삽입" on public.user_profile
  for insert with check (id = auth.uid());
create policy "user_profile: 본인만 수정" on public.user_profile
  for update using (id = auth.uid()) with check (id = auth.uid());

-- ── 2. roster — 월 단위 근무표, 날짜별 1행 ───────────────────────────────
create table public.roster (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  year int not null,
  month int not null check (month between 1 and 12),
  day int not null check (day between 1 and 31),
  shift_code text not null check (shift_code in ('D', 'E', 'N', 'O')),
  source text not null default 'manual' check (source in ('excel', 'manual', 'ocr')),
  created_at timestamptz not null default now(),
  unique (user_id, year, month, day)
);

alter table public.roster enable row level security;

create policy "roster: 본인 행만 CRUD" on public.roster
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── 3. code_mapping — 근무 코드 매핑 학습(사용자별 재사용) ────────────────
create table public.code_mapping (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  raw_code text not null,
  mapped_code text not null,
  created_at timestamptz not null default now(),
  unique (user_id, raw_code)
);

alter table public.code_mapping enable row level security;

create policy "code_mapping: 본인 행만 CRUD" on public.code_mapping
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── 4. health_session — 실측(워치) 수면 세션 ─────────────────────────────
create table public.health_session (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  start_at timestamptz not null,
  end_at timestamptz not null,
  source text not null default 'demo',
  kind text not null default 'main' check (kind in ('main', 'nap')),
  created_at timestamptz not null default now(),
  unique (user_id, start_at),
  check (end_at > start_at)
);

alter table public.health_session enable row level security;

create policy "health_session: 본인 행만 CRUD" on public.health_session
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── 5. daily_metric — 일별 계산 결과 캐시(DLMO, 수면부채 등) ──────────────
create table public.daily_metric (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  date date not null,
  dlmo_clock double precision,
  sleep_debt_min double precision,
  circular_mean_bedtime double precision,
  circular_std_bedtime double precision,
  source text not null default 'engine',
  created_at timestamptz not null default now(),
  unique (user_id, date)
);

alter table public.daily_metric enable row level security;

create policy "daily_metric: 본인 행만 CRUD" on public.daily_metric
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── 6. bedtime_intent — 취침 의도 기록 ───────────────────────────────────
create table public.bedtime_intent (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  at timestamptz not null,
  note text,
  created_at timestamptz not null default now()
);

alter table public.bedtime_intent enable row level security;

create policy "bedtime_intent: 본인 행만 CRUD" on public.bedtime_intent
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ── 7. nudge_log — 넛지 반응 로그 ────────────────────────────────────────
create table public.nudge_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  nudge_kind text not null,
  scheduled_at timestamptz not null,
  reacted_at timestamptz,
  action text check (action in ('tapped', 'dismissed', 'completed')),
  created_at timestamptz not null default now()
);

alter table public.nudge_log enable row level security;

create policy "nudge_log: 본인 행만 CRUD" on public.nudge_log
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
