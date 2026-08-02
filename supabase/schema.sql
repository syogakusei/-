-- ============================================================
-- 今日何食べる？ — Supabase 初期スキーマ
-- Supabase の SQL Editor にこの内容を貼り付けて実行してください
-- ============================================================

-- プロフィール（ニックネーム表示用。メールアドレスは公開しない）
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles are viewable by any signed-in user"
  on public.profiles for select
  to authenticated
  using (true);

create policy "users can insert their own profile"
  on public.profiles for insert
  to authenticated
  with check (id = auth.uid());

create policy "users can update their own profile"
  on public.profiles for update
  to authenticated
  using (id = auth.uid());

-- サインアップ時に自動で profiles へ行を作成する
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, nickname)
  values (new.id, coalesce(new.raw_user_meta_data->>'nickname', new.email));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- メールアドレスからユーザーIDを検索する関数（友人検索用。emailを公開テーブルに置かないため）
create function public.find_user_id_by_email(lookup_email text)
returns uuid
language sql
security definer set search_path = public
as $$
  select id from auth.users where email = lookup_email limit 1;
$$;

grant execute on function public.find_user_id_by_email(text) to authenticated;

-- 友人関係（申請→承認）
create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  addressee_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  unique (requester_id, addressee_id),
  check (requester_id <> addressee_id)
);

alter table public.friendships enable row level security;

create policy "see my own friendship rows"
  on public.friendships for select
  to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());

create policy "send friend requests as myself"
  on public.friendships for insert
  to authenticated
  with check (requester_id = auth.uid());

create policy "addressee can accept"
  on public.friendships for update
  to authenticated
  using (addressee_id = auth.uid());

create policy "either side can remove the friendship"
  on public.friendships for delete
  to authenticated
  using (requester_id = auth.uid() or addressee_id = auth.uid());

-- お気に入り・訪問記録の対象店舗
create table public.stores (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  hp_id text,
  hp_url text,
  name text not null,
  genre text,
  price text,
  moods text[] not null default '{}',
  companions text[] not null default '{}',
  memo text,
  visited boolean not null default false,
  rating int not null default 0,
  spent int not null default 0,
  visit_count int not null default 0,
  private_room boolean not null default false,
  smoking text,
  anniversary boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.stores enable row level security;

create policy "view my own stores or accepted friends' stores"
  on public.stores for select
  to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and ((f.requester_id = auth.uid() and f.addressee_id = stores.user_id)
          or (f.addressee_id = auth.uid() and f.requester_id = stores.user_id))
    )
  );

create policy "insert only my own stores"
  on public.stores for insert
  to authenticated
  with check (user_id = auth.uid());

create policy "update only my own stores"
  on public.stores for update
  to authenticated
  using (user_id = auth.uid());

create policy "delete only my own stores"
  on public.stores for delete
  to authenticated
  using (user_id = auth.uid());

-- 訪問履歴
create table public.visit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  store_id uuid references public.stores(id) on delete set null,
  store_name text not null,
  visited_at timestamptz not null default now(),
  rating int,
  spent int,
  memo text
);

alter table public.visit_logs enable row level security;

create policy "view my own visit logs or accepted friends'"
  on public.visit_logs for select
  to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.friendships f
      where f.status = 'accepted'
        and ((f.requester_id = auth.uid() and f.addressee_id = visit_logs.user_id)
          or (f.addressee_id = auth.uid() and f.requester_id = visit_logs.user_id))
    )
  );

create policy "insert only my own visit logs"
  on public.visit_logs for insert
  to authenticated
  with check (user_id = auth.uid());

-- 飯テロDM
create table public.dms (
  id uuid primary key default gen_random_uuid(),
  from_user uuid not null references auth.users(id) on delete cascade,
  to_user uuid not null references auth.users(id) on delete cascade,
  store_name text not null,
  genre text,
  msg text,
  reaction text check (reaction in ('good','bad')),
  created_at timestamptz not null default now()
);

alter table public.dms enable row level security;

create policy "see dms sent to me or by me"
  on public.dms for select
  to authenticated
  using (to_user = auth.uid() or from_user = auth.uid());

create policy "send dms as myself"
  on public.dms for insert
  to authenticated
  with check (from_user = auth.uid());

create policy "recipient can set reaction"
  on public.dms for update
  to authenticated
  using (to_user = auth.uid());
