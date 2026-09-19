alter table public.external_backup_sets drop constraint external_backup_sets_state;
alter table public.external_backup_sets add constraint external_backup_sets_state check (
  (status = 'uploading' and manifest is null and manifest_sha256 is null and verified_at is null and deleted_at is null)
  or (status in ('valid', 'deleting') and manifest is not null and manifest_sha256 is not null and verified_at is not null and deleted_at is null)
  or (status in ('failed', 'deletion_failed') and deleted_at is null)
  or (status = 'deleted' and manifest is not null and manifest_sha256 is not null and verified_at is not null and deleted_at is not null)
);

create function public.claim_expired_external_backup_set()
returns table (id uuid, storage_prefix text)
language plpgsql
security definer
set search_path = public
as $$
declare candidate public.external_backup_sets%rowtype;
begin
  with ranked as (
    select backup_set.id,
      row_number() over (partition by backup_set.business_id, backup_set.backup_kind order by backup_set.created_at desc) as position,
      case backup_set.backup_kind when 'automatic_daily' then 30 when 'automatic_monthly' then 12 else null end as keep_count
    from public.external_backup_sets backup_set
    where backup_set.status = 'valid'
      and backup_set.backup_kind in ('automatic_daily', 'automatic_monthly')
  )
  select backup_set.* into candidate
  from public.external_backup_sets backup_set
  join ranked on ranked.id = backup_set.id
  where ranked.position > ranked.keep_count
    and exists (
      select 1 from public.external_backup_sets newer
      where newer.business_id = backup_set.business_id
        and newer.backup_kind = backup_set.backup_kind
        and newer.status = 'valid'
        and newer.created_at > backup_set.created_at
    )
  order by backup_set.created_at
  limit 1
  for update skip locked;

  if not found then return; end if;
  update public.external_backup_sets set status = 'deleting' where external_backup_sets.id = candidate.id and status = 'valid';
  if not found then return; end if;
  return query select candidate.id, candidate.storage_prefix;
end;
$$;

revoke all on function public.claim_expired_external_backup_set() from public;
grant execute on function public.claim_expired_external_backup_set() to service_role;
