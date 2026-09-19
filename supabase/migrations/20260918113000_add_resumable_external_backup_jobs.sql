-- Los conjuntos externos se preparan por lotes para no exceder el límite de
-- una Edge Function. Un job incompleto nunca es restaurable ni entra en retención.

create type public.external_backup_job_status as enum (
  'pending', 'exporting', 'copying_attachments', 'verifying', 'finalizing', 'completed', 'failed'
);

create type public.external_backup_file_status as enum ('pending', 'verified', 'failed');

create table public.external_backup_jobs (
  id uuid primary key,
  backup_set_id uuid not null unique references public.external_backup_sets(id) on delete restrict,
  business_id uuid not null references public.businesses(id) on delete restrict,
  backup_kind public.business_backup_kind not null,
  status public.external_backup_job_status not null default 'pending',
  total_files integer not null default 0 check (total_files >= 0),
  verified_files integer not null default 0 check (verified_files >= 0),
  total_attachments integer not null default 0 check (total_attachments >= 0),
  verified_attachments integer not null default 0 check (verified_attachments >= 0),
  verification_cursor integer not null default 0 check (verification_cursor >= 0),
  progress_percent numeric(5, 2) not null default 0 check (progress_percent between 0 and 100),
  timing_ms jsonb not null default '{}'::jsonb check (jsonb_typeof(timing_ms) = 'object'),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  error_message text,
  lease_token uuid,
  lease_expires_at timestamptz,
  last_started_at timestamptz,
  last_completed_at timestamptz,
  cleanup_completed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint external_backup_jobs_counts check (verified_files <= total_files and verified_attachments <= total_attachments),
  constraint external_backup_jobs_terminal check (
    (status = 'completed' and progress_percent = 100 and error_message is null)
    or (status <> 'completed')
  )
);

create table public.external_backup_job_files (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.external_backup_jobs(id) on delete restrict,
  ordinal integer not null check (ordinal >= 0),
  file_kind text not null check (file_kind in ('data', 'structured_export', 'attachment')),
  object_key text not null check (char_length(btrim(object_key)) between 1 and 700),
  mime_type text not null check (char_length(btrim(mime_type)) between 1 and 255),
  source_bucket_id text,
  source_name text,
  related_record text,
  size_bytes bigint,
  checksum_sha256 text check (checksum_sha256 is null or checksum_sha256 ~ '^[0-9a-f]{64}$'),
  status public.external_backup_file_status not null default 'pending',
  verified_at timestamptz,
  failure_reason text,
  cleanup_deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint external_backup_job_files_order_unique unique (job_id, ordinal),
  constraint external_backup_job_files_source check (
    (file_kind = 'attachment' and source_bucket_id is not null and source_name is not null)
    or (file_kind <> 'attachment' and source_bucket_id is null and source_name is null)
  ),
  constraint external_backup_job_files_verified check (
    (status = 'verified' and size_bytes is not null and checksum_sha256 is not null and verified_at is not null)
    or (status <> 'verified')
  )
);

create index external_backup_jobs_work_idx on public.external_backup_jobs (status, lease_expires_at, created_at);
create index external_backup_job_files_work_idx on public.external_backup_job_files (job_id, status, ordinal);

create trigger set_external_backup_jobs_updated_at before update on public.external_backup_jobs
  for each row execute procedure public.set_updated_at();
create trigger set_external_backup_job_files_updated_at before update on public.external_backup_job_files
  for each row execute procedure public.set_updated_at();

alter table public.external_backup_jobs enable row level security;
alter table public.external_backup_job_files enable row level security;
create policy "owners read their external backup jobs" on public.external_backup_jobs
  for select to authenticated using (public.is_business_owner(business_id));
create policy "owners read their external backup job files" on public.external_backup_job_files
  for select to authenticated using (exists (
    select 1 from public.external_backup_jobs job where job.id = job_id and public.is_business_owner(job.business_id)
  ));

create function public.claim_external_backup_job(p_job_id uuid, p_lease_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare job_row public.external_backup_jobs%rowtype;
begin
  update public.external_backup_jobs
  set lease_token = p_lease_token,
      lease_expires_at = now() + interval '120 seconds',
      last_started_at = now(),
      attempt_count = attempt_count + 1
  where id = p_job_id
    and status in ('pending', 'exporting', 'copying_attachments', 'verifying', 'finalizing')
    and (lease_expires_at is null or lease_expires_at < now())
  returning * into job_row;
  if not found then return null; end if;
  return to_jsonb(job_row);
end;
$$;

create function public.get_external_backup_job_status(p_job_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare job_row public.external_backup_jobs%rowtype;
begin
  select * into job_row from public.external_backup_jobs where id = p_job_id;
  if not found then raise exception 'El trabajo de respaldo no existe.'; end if;
  if auth.role() <> 'service_role' and (auth.uid() is null or not public.is_business_owner(job_row.business_id)) then
    raise exception 'No tienes permiso para consultar este respaldo.';
  end if;
  return jsonb_build_object(
    'id', job_row.id, 'status', job_row.status, 'progress_percent', job_row.progress_percent,
    'total_files', job_row.total_files, 'verified_files', job_row.verified_files,
    'total_attachments', job_row.total_attachments, 'verified_attachments', job_row.verified_attachments,
    'error_message', job_row.error_message, 'timing_ms', job_row.timing_ms,
    'updated_at', job_row.updated_at
  );
end;
$$;

revoke all on function public.claim_external_backup_job(uuid, uuid) from public;
grant execute on function public.claim_external_backup_job(uuid, uuid) to service_role;
revoke all on function public.get_external_backup_job_status(uuid) from public;
grant execute on function public.get_external_backup_job_status(uuid) to authenticated, service_role;
