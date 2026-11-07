-- =====================================================================
-- WMS Gudang Spare Part - PT Indonesia Prima Equipment Cabang Sampit
-- Jalankan SEKALI di Supabase: SQL Editor > New query > paste > Run
-- =====================================================================

-- 1) Tabel profil pengguna + peran
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text default '',
  role text not null default 'pending' check (role in ('admin','staff','viewer','pending')),
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- fungsi pembantu: peran user yang sedang login
create or replace function public.my_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

-- user pertama yang dibuat otomatis jadi admin; berikutnya 'pending' (menunggu diberi peran oleh admin)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name, role)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name',''),
          case when not exists (select 1 from public.profiles) then 'admin' else 'pending' end);
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create policy "profiles_select" on public.profiles for select to authenticated
  using (id = auth.uid() or public.my_role() in ('admin','staff','viewer'));
create policy "profiles_update_admin" on public.profiles for update to authenticated
  using (public.my_role() = 'admin') with check (public.my_role() = 'admin');

-- 2) Tabel data (parts, movements, customers, suppliers, pos)
do $$
declare t text;
begin
  foreach t in array array['parts','movements','customers','suppliers','pos'] loop
    execute format('create table if not exists public.%I (
      id uuid primary key default gen_random_uuid(),
      data jsonb not null default ''{}''::jsonb,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now())', t);
    execute format('alter table public.%I enable row level security', t);

    -- lihat: admin, staf, viewer
    execute format('create policy "%s_select" on public.%I for select to authenticated
      using (public.my_role() in (''admin'',''staff'',''viewer''))', t, t);
    -- tambah: admin, staf
    execute format('create policy "%s_insert" on public.%I for insert to authenticated
      with check (public.my_role() in (''admin'',''staff''))', t, t);
    -- ubah: admin & staf (riwayat transaksi hanya admin, supaya kartu stok tidak bisa diutak-atik)
    execute format('create policy "%s_update" on public.%I for update to authenticated
      using (public.my_role() in (%s)) with check (public.my_role() in (%s))', t, t,
      case when t = 'movements' then '''admin''' else '''admin'',''staff''' end,
      case when t = 'movements' then '''admin''' else '''admin'',''staff''' end);
    -- hapus: admin saja
    execute format('create policy "%s_delete" on public.%I for delete to authenticated
      using (public.my_role() = ''admin'')', t, t);

    -- realtime (data tampil otomatis di semua perangkat)
    execute format('alter publication supabase_realtime add table public.%I', t);
  end loop;
end $$;
