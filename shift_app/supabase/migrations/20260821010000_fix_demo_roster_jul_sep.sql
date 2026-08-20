-- 심사용 데모 계정의 근무표를 2026년 7~9월로 고정한다.
-- 기존에 잘못 들어간 9~11월 데이터는 전부 교체한다.
do $$
declare
  demo_user_id uuid;
begin
  select id
    into demo_user_id
    from auth.users
   where lower(email) = 'demo@sleepready.app'
   limit 1;

  if demo_user_id is null then
    raise notice 'demo@sleepready.app 계정이 없어 근무표 시드를 건너뜁니다.';
    return;
  end if;

  delete from public.roster_entries
   where user_id = demo_user_id;

  insert into public.roster_entries (user_id, work_date, shift_type)
  select
    demo_user_id,
    work_date::date,
    (array['D', 'D', 'E', 'E', 'N', 'N', 'O', 'O', 'D', 'E', 'N', 'O'])[
      (work_date::date - date '2026-07-01') % 12 + 1
    ]
  from generate_series(
    date '2026-07-01',
    date '2026-09-30',
    interval '1 day'
  ) as work_date;
end
$$;
