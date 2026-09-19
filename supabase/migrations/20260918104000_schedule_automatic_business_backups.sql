-- Respaldos diarios privados en PostgreSQL. Los adjuntos quedan inventariados
-- en el manifiesto; los archivos originales permanecen en Storage privado.

create function public.run_automatic_business_backups()
returns integer
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  business_row record;
  payload jsonb;
  checksum text;
  created_count integer := 0;
  daily_cutoff timestamptz := now() - interval '30 days';
  monthly_cutoff timestamptz := now() - interval '12 months';
begin
  for business_row in select id from public.businesses loop
    payload := public.build_business_structured_export(business_row.id);
    checksum := encode(digest(convert_to(payload::text, 'UTF8'), 'sha256'), 'hex');
    insert into public.business_backups (business_id, backup_kind, snapshot, manifest, checksum_sha256)
    values (
      business_row.id, 'automatic_daily', payload,
      jsonb_build_object('format', 'almacen-el-amigo-backup-v1', 'attachments_included', payload -> 'attachments_manifest', 'checksum_algorithm', 'sha256'),
      checksum
    );
    if extract(day from now() at time zone 'America/Guatemala') = 1 then
      insert into public.business_backups (business_id, backup_kind, snapshot, manifest, checksum_sha256)
      values (
        business_row.id, 'automatic_monthly', payload,
        jsonb_build_object('format', 'almacen-el-amigo-backup-v1', 'attachments_included', payload -> 'attachments_manifest', 'checksum_algorithm', 'sha256'),
        checksum
      );
    end if;
    created_count := created_count + 1;
  end loop;

  delete from public.business_backups backup
  where backup.backup_kind = 'automatic_daily' and backup.created_at < daily_cutoff;
  delete from public.business_backups backup
  where backup.backup_kind = 'automatic_monthly' and backup.created_at < monthly_cutoff;
  return created_count;
end;
$$;

create extension if not exists pg_cron;

do $$
declare scheduled_job_id bigint;
begin
  select jobid into scheduled_job_id from cron.job where jobname = 'almacen-el-amigo-daily-backups';
  if scheduled_job_id is not null then perform cron.unschedule(scheduled_job_id); end if;
  perform cron.schedule(
    'almacen-el-amigo-daily-backups',
    '0 8 * * *',
    'select public.run_automatic_business_backups();'
  );
end;
$$;
