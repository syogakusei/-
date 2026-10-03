-- ============================================================
-- 日調くん — 追加分その2（MTG時間が時間帯で割り切れなくてもOKにする）
-- migrate-001 を実行済みのデータベースに、この内容を1回だけ実行してください。
-- データは消えません（時間帯のチェック条件を差し替えるだけです）。
-- ============================================================

alter table public.nitcho_events drop constraint nitcho_events_range_fits_slot;

alter table public.nitcho_events
  add constraint nitcho_events_range_fits_slot check (end_min - start_min >= slot_min);

create or replace function public.nitcho_create_event(
  p_title text, p_description text, p_dates date[], p_start int, p_end int, p_slot int default 30
)
returns uuid
language plpgsql
security definer set search_path = public
as $$
declare
  new_id uuid;
begin
  if (((p_end - p_start - p_slot) / 30) + 1) * cardinality(p_dates) > 3000 then
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
