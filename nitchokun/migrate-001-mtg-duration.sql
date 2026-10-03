-- ============================================================
-- 日調くん — 追加分（MTG時間）
-- すでに schema.sql を実行したデータベースに、この内容を1回だけ実行してください。
-- （これから新しく作る場合は schema.sql だけでOK。こちらは不要です）
-- ============================================================

alter table public.nitcho_events
  add column slot_min int not null default 30
  check (slot_min between 30 and 1440 and slot_min % 30 = 0);

alter table public.nitcho_events
  add constraint nitcho_events_range_fits_slot check ((end_min - start_min) % slot_min = 0);

drop function public.nitcho_create_event(text, text, date[], int, int);

create function public.nitcho_create_event(
  p_title text, p_description text, p_dates date[], p_start int, p_end int, p_slot int default 30
)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  new_id uuid;
begin
  if ((p_end - p_start) / p_slot) * cardinality(p_dates) > 3000 then
    raise exception '候補のマスが多すぎます（日数か時間帯を減らしてください）';
  end if;
  insert into nitcho_events (title, description, dates, start_min, end_min, slot_min)
  values (
    trim(p_title), coalesce(p_description, ''),
    (select array_agg(d order by d) from (select distinct unnest(p_dates) as d) s),
    p_start, p_end, p_slot
  )
  returning id into new_id;
  return new_id;
end;
$$;

create or replace function public.nitcho_get_event(p_id uuid)
returns json
language sql
stable
security definer set search_path = public
as $$
  select json_build_object(
    'event', json_build_object(
      'id', e.id, 'title', e.title, 'description', e.description,
      'dates', e.dates, 'start_min', e.start_min, 'end_min', e.end_min,
      'slot_min', e.slot_min
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

grant execute on function public.nitcho_create_event(text, text, date[], int, int, int) to anon, authenticated;
