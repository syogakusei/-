-- ============================================================
-- 日調くん — Supabase スキーマ
-- Supabase の SQL Editor にこの内容を貼り付けて実行してください。
-- 日調くん専用の Supabase プロジェクトで実行します。
--
-- ログイン不要で「リンクを知っている人だけ」が見られるようにするため、
-- テーブルは直接読めないようにして（RLS有効・ポリシーなし）、
-- イベントIDを指定する関数（RPC）経由でのみ読み書きします。
-- ============================================================

create table public.nitcho_events (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(title) between 1 and 100),
  description text not null default '' check (char_length(description) <= 1000),
  dates date[] not null check (cardinality(dates) between 1 and 62),
  start_min int not null check (start_min between 0 and 1410 and start_min % 30 = 0),
  end_min int not null check (end_min between 30 and 1440 and end_min % 30 = 0),
  created_at timestamptz not null default now(),
  check (end_min > start_min)
);

create table public.nitcho_responses (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.nitcho_events(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 30),
  -- {"2026-10-02|540": "o" | "t" | "x"}  （o=○, t=△, x=×、540 = 9:00 を分で表したもの）
  answers jsonb not null default '{}'::jsonb,
  -- {"2026-10-02|540": "遅れるかも"}
  comments jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, name),
  check (jsonb_typeof(answers) = 'object' and jsonb_typeof(comments) = 'object'),
  check (octet_length(answers::text) <= 100000 and octet_length(comments::text) <= 200000)
);

alter table public.nitcho_events enable row level security;
alter table public.nitcho_responses enable row level security;
-- ポリシーは作らない＝anon キーからテーブルを直接読めない（一覧取得もできない）

-- 接続確認用
create function public.nitcho_ping()
returns text
language sql
as $$ select 'ok'::text; $$;

-- イベント作成
create function public.nitcho_create_event(
  p_title text, p_description text, p_dates date[], p_start int, p_end int
)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  new_id uuid;
begin
  if ((p_end - p_start) / 30) * cardinality(p_dates) > 3000 then
    raise exception '候補のマスが多すぎます（日数か時間帯を減らしてください）';
  end if;
  insert into nitcho_events (title, description, dates, start_min, end_min)
  values (
    trim(p_title), coalesce(p_description, ''),
    (select array_agg(d order by d) from (select distinct unnest(p_dates) as d) s),
    p_start, p_end
  )
  returning id into new_id;
  return new_id;
end;
$$;

-- イベントと全員の回答を取得
create function public.nitcho_get_event(p_id uuid)
returns json
language sql
stable
security definer set search_path = public
as $$
  select json_build_object(
    'event', json_build_object(
      'id', e.id, 'title', e.title, 'description', e.description,
      'dates', e.dates, 'start_min', e.start_min, 'end_min', e.end_min
    ),
    'responses', coalesce((
      select json_agg(json_build_object(
        'name', r.name, 'answers', r.answers, 'comments', r.comments, 'updated_at', r.updated_at
      ) order by r.created_at)
      from nitcho_responses r where r.event_id = e.id
    ), '[]'::json)
  )
  from nitcho_events e
  where e.id = p_id;
$$;

-- 回答を保存（同じ名前なら上書き）
create function public.nitcho_save_response(
  p_event uuid, p_name text, p_answers jsonb, p_comments jsonb
)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not exists (select 1 from nitcho_events where id = p_event) then
    raise exception 'イベントが見つかりません';
  end if;
  insert into nitcho_responses (event_id, name, answers, comments)
  values (p_event, trim(p_name), coalesce(p_answers, '{}'::jsonb), coalesce(p_comments, '{}'::jsonb))
  on conflict (event_id, name) do update
    set answers = excluded.answers,
        comments = excluded.comments,
        updated_at = now();
end;
$$;

-- 回答者の名前を変更
create function public.nitcho_rename_response(p_event uuid, p_old text, p_new text)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  update nitcho_responses
     set name = trim(p_new), updated_at = now()
   where event_id = p_event and name = p_old;
exception
  when unique_violation then
    raise exception 'その名前はすでに使われています';
end;
$$;

-- 回答を削除
create function public.nitcho_delete_response(p_event uuid, p_name text)
returns void
language sql
security definer set search_path = public
as $$
  delete from nitcho_responses where event_id = p_event and name = p_name;
$$;

grant execute on function public.nitcho_ping() to anon, authenticated;
grant execute on function public.nitcho_create_event(text, text, date[], int, int) to anon, authenticated;
grant execute on function public.nitcho_get_event(uuid) to anon, authenticated;
grant execute on function public.nitcho_save_response(uuid, text, jsonb, jsonb) to anon, authenticated;
grant execute on function public.nitcho_rename_response(uuid, text, text) to anon, authenticated;
grant execute on function public.nitcho_delete_response(uuid, text) to anon, authenticated;
