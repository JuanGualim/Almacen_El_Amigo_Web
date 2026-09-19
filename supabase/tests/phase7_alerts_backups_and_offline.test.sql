begin;

select plan(17);

insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('99999999-9999-9999-9999-999999999991', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'phase7-owner@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('99999999-9999-9999-9999-999999999992', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'phase7-employee@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('99999999-9999-9999-9999-999999999993', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'phase7-outsider@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

create temporary table phase7_context (business_id uuid, variant_id uuid, cash_session_id uuid, conflict_id uuid);
grant select, insert, update on phase7_context to authenticated, service_role;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999991', true);

insert into phase7_context (business_id) select public.create_business('Negocio fase siete');
update phase7_context set variant_id = public.create_catalog_product(business_id, 'Camisas', null, 'Camisa alerta', '{}'::jsonb, '{"size":"M"}'::jsonb, 100.00, 80.00);

select is((select out_of_stock_count from public.get_inventory_alerts((select business_id from phase7_context))), 1, 'una variante sin disponible aparece agotada');
select is((select (variants -> 0 ->> 'low_stock_threshold')::integer from public.get_inventory_alerts((select business_id from phase7_context))), 2, 'el límite predeterminado es dos unidades');

select lives_ok($$ select public.set_variant_stock_alert((select business_id from phase7_context), (select variant_id from phase7_context), 3, false) $$, 'el dueño puede desactivar una alerta por variante');
select is((select count(*) from public.get_inventory_alerts((select business_id from phase7_context))), 0::bigint, 'una alerta desactivada no se presenta');

update phase7_context set cash_session_id = public.open_cash_register(business_id, 0, null, '99999999-0000-4000-8000-000000000001');
update phase7_context set conflict_id = public.record_offline_sale_sync_conflict(
  business_id, cash_session_id, 'cash', jsonb_build_array(jsonb_build_object('variant_id', variant_id, 'quantity', 1, 'unit_price', 100.00)),
  'No hubo existencias al sincronizar.', '99999999-0000-4000-8000-000000000002'
);

select is((select status::text from public.offline_sale_sync_conflicts where id = (select conflict_id from phase7_context)), 'open', 'un rechazo de venta offline conserva el conflicto');
select lives_ok($$ select public.resolve_offline_sale_sync_conflict((select business_id from phase7_context), (select conflict_id from phase7_context), 'Se registró una venta corregida.') $$, 'el dueño puede resolver el conflicto con nota');
select is((select status::text from public.offline_sale_sync_conflicts where id = (select conflict_id from phase7_context)), 'resolved', 'la resolución queda inmutable y auditada');

select ok((select checksum_sha256 ~ '^[0-9a-f]{64}$' from public.create_manual_business_backup((select business_id from phase7_context))), 'el respaldo manual tiene suma sha256');
select is((select get_business_structured_export((select business_id from phase7_context)) ->> 'format'), 'almacen-el-amigo-structured-export-v1', 'la exportación JSON tiene formato versionado');
select is((select get_business_backup_data((select business_id from phase7_context)) ->> 'format'), 'almacen-el-amigo-backup-data-v2', 'el respaldo externo obtiene datos lógicos versionados');

set local role service_role;
insert into public.external_backup_sets (id, business_id, backup_kind, storage_provider, storage_prefix, created_by)
select '99999999-9999-4999-8999-999999999994', business_id, 'manual', 's3-compatible', 'backup-sets/phase7/incomplete', '99999999-9999-9999-9999-999999999991' from phase7_context;
insert into public.external_backup_jobs (id, backup_set_id, business_id, backup_kind, created_by)
select '99999999-9999-4999-8999-999999999994', '99999999-9999-4999-8999-999999999994', business_id, 'manual', '99999999-9999-9999-9999-999999999991' from phase7_context;

select is((select (public.claim_external_backup_job('99999999-9999-4999-8999-999999999994', '99999999-9999-4999-8999-999999999995') ->> 'status')), 'pending', 'el primer lote reserva un trabajo pendiente');
select is((select public.claim_external_backup_job('99999999-9999-4999-8999-999999999994', '99999999-9999-4999-8999-999999999996')), null, 'una doble invocación no reserva el mismo lote');
select is((select status::text from public.external_backup_sets where id = '99999999-9999-4999-8999-999999999994'), 'uploading', 'un conjunto incompleto no es válido ni restaurable');
select throws_ok($$ insert into public.external_backup_job_files (job_id, ordinal, file_kind, object_key, mime_type, status) values ('99999999-9999-4999-8999-999999999994', 0, 'data', 'backup-sets/phase7/data.json', 'application/json', 'verified') $$, '23514', null, 'un archivo no se marca verificado sin tamaño y checksum');

insert into public.external_backup_sets (id, business_id, backup_kind, status, storage_provider, storage_prefix, manifest, manifest_sha256, verified_at, created_at)
select gen_random_uuid(), business_id, 'automatic_daily', 'valid', 's3-compatible', 'backup-sets/phase7/retention/' || series, '{}'::jsonb, repeat('0', 64), now(), now() - (series || ' days')::interval
from phase7_context cross join generate_series(1, 31) series;
select ok((select id is not null from public.claim_expired_external_backup_set()), 'la retención selecciona solo una diaria válida vencida cuando existe una más reciente');

set local role service_role;
insert into public.business_memberships (business_id, user_id, role_id, status, created_by)
select context.business_id, '99999999-9999-9999-9999-999999999992', role.id, 'active', '99999999-9999-9999-9999-999999999991'
from phase7_context context join public.business_roles role on role.business_id = context.business_id and role.code = 'employee';

set local role authenticated;
select set_config('request.jwt.claim.sub', '99999999-9999-9999-9999-999999999992', true);
select throws_ok($$ select public.set_variant_stock_alert((select business_id from phase7_context), (select variant_id from phase7_context), 2, true) $$, 'P0001', 'Solo el dueño puede configurar alertas de existencias.', 'un empleado no configura alertas');
select throws_ok($$ select public.get_business_structured_export((select business_id from phase7_context)) $$, 'P0001', 'Solo el dueño puede generar una exportación estructurada.', 'un empleado no descarga exportación completa');

select * from finish();
rollback;
