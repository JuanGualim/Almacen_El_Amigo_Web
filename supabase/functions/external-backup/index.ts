import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2'
import { createS3CompatibleStorage, putAndVerifyObject, verifyExistingObject } from '../_shared/s3-compatible.mjs'
import { ATTACHMENTS_PER_INVOCATION, calculateProgress, canFinalize, nextPendingFiles, nextVerificationFiles, resumeStatus, sanitizeBackupError, shouldFinalize, VERIFICATIONS_PER_INVOCATION } from '../_shared/backup-job-state.mjs'

type BackupKind = 'manual' | 'automatic_daily' | 'automatic_monthly'
type JobStatus = 'pending' | 'exporting' | 'copying_attachments' | 'verifying' | 'finalizing' | 'completed' | 'failed'
type Action = 'start' | 'process' | 'retry' | 'status' | 'start_automatic' | 'process_pending' | 'cleanup'
type BackupRequest = { action?: unknown; businessId?: unknown; jobId?: unknown; kind?: unknown }
type Storage = ReturnType<typeof createS3CompatibleStorage>
type Job = { id: string; backup_set_id: string; business_id: string; backup_kind: BackupKind; status: JobStatus; timing_ms: Record<string, number>; total_files: number; verified_files: number; total_attachments: number; verified_attachments: number; verification_cursor: number; attempt_count: number; created_by: string | null }
type JobFile = { id: string; ordinal: number; file_kind: 'data' | 'structured_export' | 'attachment'; object_key: string; mime_type: string; source_bucket_id: string | null; source_name: string | null; related_record: string | null; size_bytes: number | null; checksum_sha256: string | null; status: 'pending' | 'verified' | 'failed'; cleanup_deleted_at?: string | null }
type AttachmentSource = { bucket_id?: unknown; name?: unknown; metadata?: unknown }

const corsHeaders = { 'Access-Control-Allow-Headers': 'authorization, x-backup-job-token, x-client-info, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Origin': '*' }
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const INCOMPLETE_RETENTION_DAYS = 7

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false
  let result = 0
  for (let index = 0; index < left.length; index += 1) result |= left.charCodeAt(index) ^ right.charCodeAt(index)
  return result === 0
}

function readConfig(): { storage: Storage; jobToken: string } {
  const endpoint = Deno.env.get('BACKUP_S3_ENDPOINT'); const bucket = Deno.env.get('BACKUP_S3_BUCKET'); const accessKeyId = Deno.env.get('BACKUP_S3_ACCESS_KEY_ID'); const secretAccessKey = Deno.env.get('BACKUP_S3_SECRET_ACCESS_KEY'); const jobToken = Deno.env.get('BACKUP_JOB_TOKEN')
  if (!endpoint || !bucket || !accessKeyId || !secretAccessKey || !jobToken) throw new Error('El respaldo externo no está configurado en el servidor.')
  return { storage: createS3CompatibleStorage({ endpoint, bucket, accessKeyId, secretAccessKey, region: Deno.env.get('BACKUP_S3_REGION') ?? 'auto' }), jobToken }
}

function readRequest(payload: BackupRequest): { action: Action; businessId: string | null; jobId: string | null; kind: BackupKind | null } {
  const action = typeof payload.action === 'string' ? payload.action : 'start'; const businessId = typeof payload.businessId === 'string' ? payload.businessId : null; const jobId = typeof payload.jobId === 'string' ? payload.jobId : null; const kind = typeof payload.kind === 'string' ? payload.kind : null
  if (!['start', 'process', 'retry', 'status', 'start_automatic', 'process_pending', 'cleanup'].includes(action)) throw new Error('La acción de respaldo no es válida.')
  if (businessId && !UUID_PATTERN.test(businessId)) throw new Error('El negocio solicitado no es válido.')
  if (jobId && !UUID_PATTERN.test(jobId)) throw new Error('El trabajo solicitado no es válido.')
  if (kind && !['manual', 'automatic_daily', 'automatic_monthly'].includes(kind)) throw new Error('El tipo de respaldo no es válido.')
  return { action: action as Action, businessId, jobId, kind: kind as BackupKind | null }
}

function contentTypeFromMetadata(metadata: unknown): string {
  const value = metadata && typeof metadata === 'object' ? (metadata as Record<string, unknown>).mimetype : null
  return typeof value === 'string' && value.length > 0 ? value : 'application/octet-stream'
}

function relatedRecordFromMetadata(metadata: unknown): string | null {
  if (!metadata || typeof metadata !== 'object') return null
  const values = metadata as Record<string, unknown>
  return ['related_record_id', 'record_id', 'entity_id'].map((key) => values[key]).find((value): value is string => typeof value === 'string' && value.length > 0) ?? null
}

async function isBusinessOwner(admin: SupabaseClient, businessId: string, userId: string): Promise<boolean> {
  const { data, error } = await admin.from('business_memberships').select('business_roles!inner(code)').eq('business_id', businessId).eq('user_id', userId).eq('status', 'active').limit(1)
  const role = data?.[0]?.business_roles as unknown as { code?: string } | { code?: string }[] | null
  return !error && (Array.isArray(role) ? role[0]?.code : role?.code) === 'owner'
}

async function getJob(admin: SupabaseClient, jobId: string): Promise<Job> {
  const { data, error } = await admin.from('external_backup_jobs').select('*').eq('id', jobId).single()
  if (error || !data) throw new Error('El trabajo de respaldo no está disponible.')
  return data as Job
}

async function getFiles(admin: SupabaseClient, jobId: string): Promise<JobFile[]> {
  const { data, error } = await admin.from('external_backup_job_files').select('*').eq('job_id', jobId).order('ordinal')
  if (error || !data) throw new Error('No fue posible consultar el progreso del respaldo.')
  return data as JobFile[]
}

async function updateJob(admin: SupabaseClient, job: Job, leaseToken: string, values: Record<string, unknown>): Promise<void> {
  const { data, error } = await admin.from('external_backup_jobs').update({ ...values, lease_expires_at: null, last_completed_at: new Date().toISOString() }).eq('id', job.id).eq('lease_token', leaseToken).select('id')
  if (error || !data?.length) throw new Error('No fue posible guardar el punto de control del respaldo.')
}

async function checkpointTiming(admin: SupabaseClient, job: Job, leaseToken: string, timing: Record<string, number>): Promise<void> {
  if (Object.keys(timing).length === 0) return
  const accumulated = { ...(job.timing_ms ?? {}) }
  for (const [key, value] of Object.entries(timing)) accumulated[key] = (accumulated[key] ?? 0) + Math.round(value)
  const { data, error } = await admin.from('external_backup_jobs').update({ timing_ms: accumulated }).eq('id', job.id).eq('lease_token', leaseToken).select('id')
  if (error || !data?.length) throw new Error('No fue posible guardar los tiempos del respaldo.')
  job.timing_ms = accumulated
}

async function updateProgress(admin: SupabaseClient, job: Job, leaseToken: string, status: JobStatus, files: JobFile[], timing: Record<string, number>, extra: Record<string, unknown> = {}): Promise<void> {
  const verifiedFiles = files.filter((file) => file.status === 'verified').length; const verifiedAttachments = files.filter((file) => file.status === 'verified' && file.file_kind === 'attachment').length; const totalAttachments = files.filter((file) => file.file_kind === 'attachment').length
  const accumulatedTiming = { ...(job.timing_ms ?? {}) }
  for (const [key, value] of Object.entries(timing)) accumulatedTiming[key] = (accumulatedTiming[key] ?? 0) + Math.round(value)
  await updateJob(admin, job, leaseToken, { status, total_files: files.length, verified_files: verifiedFiles, total_attachments: totalAttachments, verified_attachments: verifiedAttachments, progress_percent: calculateProgress(files.length, verifiedFiles, status), timing_ms: accumulatedTiming, ...extra })
}

async function startJob(admin: SupabaseClient, businessId: string, kind: BackupKind, createdBy: string | null): Promise<string> {
  const { data: existing } = await admin.from('external_backup_jobs').select('id').eq('business_id', businessId).eq('backup_kind', kind).in('status', ['pending', 'exporting', 'copying_attachments', 'verifying', 'finalizing']).order('created_at', { ascending: false }).limit(1)
  if (existing?.[0]?.id) return existing[0].id
  const jobId = crypto.randomUUID(); const prefix = `backup-sets/${businessId}/${kind}/${jobId}`
  const { error: setError } = await admin.from('external_backup_sets').insert({ id: jobId, business_id: businessId, backup_kind: kind, storage_provider: 's3-compatible', storage_prefix: prefix, created_by: createdBy })
  if (setError) throw new Error('No fue posible crear el conjunto de respaldo.')
  const { error: jobError } = await admin.from('external_backup_jobs').insert({ id: jobId, backup_set_id: jobId, business_id: businessId, backup_kind: kind, created_by: createdBy })
  if (jobError) { await admin.from('external_backup_sets').update({ status: 'failed', failure_reason: 'No fue posible iniciar el trabajo de respaldo.' }).eq('id', jobId); throw new Error('No fue posible iniciar el trabajo de respaldo.') }
  return jobId
}

async function claimJob(admin: SupabaseClient, jobId: string): Promise<{ job: Job; leaseToken: string } | null> {
  const leaseToken = crypto.randomUUID(); const { data, error } = await admin.rpc('claim_external_backup_job', { p_job_id: jobId, p_lease_token: leaseToken })
  if (error) throw new Error('No fue posible reservar el lote del respaldo.')
  return data ? { job: data as Job, leaseToken } : null
}

async function prepareExports(admin: SupabaseClient, storage: Storage, job: Job, leaseToken: string): Promise<void> {
  const { data: backupSet, error: setError } = await admin.from('external_backup_sets').select('storage_prefix').eq('id', job.backup_set_id).single()
  if (setError || !backupSet) throw new Error('No fue posible ubicar el conjunto de respaldo.')
  const existingFiles = await getFiles(admin, job.id)
  const timings: Record<string, number> = {}
  if (!existingFiles.some((file) => file.file_kind === 'data' && file.status === 'verified')) {
    const dataStarted = performance.now()
    const { data: dataBackup, error: dataError } = await admin.rpc('get_business_backup_data', { p_business_id: job.business_id })
    timings.data_generation = performance.now() - dataStarted
    if (dataError || !dataBackup) throw new Error('No fue posible generar los datos del respaldo.')
    const uploadStarted = performance.now()
    const verified = await putAndVerifyObject(storage, `${backupSet.storage_prefix}/data/backup-data.json`, new TextEncoder().encode(`${JSON.stringify(dataBackup)}\n`), 'application/json')
    timings.data_upload_and_verify = performance.now() - uploadStarted
    const { error } = await admin.from('external_backup_job_files').upsert({ job_id: job.id, ordinal: 0, file_kind: 'data', object_key: `${backupSet.storage_prefix}/data/backup-data.json`, mime_type: 'application/json', size_bytes: verified.sizeBytes, checksum_sha256: verified.sha256, status: 'verified', verified_at: new Date().toISOString() }, { onConflict: 'job_id,ordinal' })
    if (error) throw new Error('No fue posible guardar el punto de control de datos.')
    await checkpointTiming(admin, job, leaseToken, timings)
    Object.keys(timings).forEach((key) => delete timings[key])
  }

  let structuredExport: { attachments_manifest?: AttachmentSource[] } | null = null
  if (!existingFiles.some((file) => file.file_kind === 'structured_export' && file.status === 'verified') || !existingFiles.some((file) => file.file_kind === 'attachment')) {
    const structuredStarted = performance.now()
    const { data, error: exportError } = await admin.rpc('get_business_structured_export', { p_business_id: job.business_id })
    timings.structured_export_generation = performance.now() - structuredStarted
    if (exportError || !data) throw new Error('No fue posible generar la exportación estructurada.')
    structuredExport = data as { attachments_manifest?: AttachmentSource[] }
  }
  if (!existingFiles.some((file) => file.file_kind === 'structured_export' && file.status === 'verified')) {
    const uploadStarted = performance.now()
    const verified = await putAndVerifyObject(storage, `${backupSet.storage_prefix}/exports/structured-export.json`, new TextEncoder().encode(`${JSON.stringify(structuredExport)}\n`), 'application/json')
    timings.structured_export_upload_and_verify = performance.now() - uploadStarted
    const { error } = await admin.from('external_backup_job_files').upsert({ job_id: job.id, ordinal: 1, file_kind: 'structured_export', object_key: `${backupSet.storage_prefix}/exports/structured-export.json`, mime_type: 'application/json', size_bytes: verified.sizeBytes, checksum_sha256: verified.sha256, status: 'verified', verified_at: new Date().toISOString() }, { onConflict: 'job_id,ordinal' })
    if (error) throw new Error('No fue posible guardar el punto de control de la exportación.')
    await checkpointTiming(admin, job, leaseToken, timings)
    Object.keys(timings).forEach((key) => delete timings[key])
  }

  const rows: Record<string, unknown>[] = []
  const attachments = structuredExport?.attachments_manifest ?? []
  if (!Array.isArray(attachments)) throw new Error('El manifiesto de adjuntos no tiene un formato válido.')
  for (const [index, attachment] of attachments.entries()) {
    if (typeof attachment.bucket_id !== 'string' || typeof attachment.name !== 'string') throw new Error('Se encontró un adjunto sin ruta válida.')
    rows.push({ job_id: job.id, ordinal: index + 2, file_kind: 'attachment', object_key: `${backupSet.storage_prefix}/attachments/${encodeURIComponent(attachment.bucket_id)}/${attachment.name.split('/').map(encodeURIComponent).join('/')}`, mime_type: contentTypeFromMetadata(attachment.metadata), source_bucket_id: attachment.bucket_id, source_name: attachment.name, related_record: relatedRecordFromMetadata(attachment.metadata), status: 'pending' })
  }
  if (rows.length > 0) {
    const { error: filesError } = await admin.from('external_backup_job_files').upsert(rows, { onConflict: 'job_id,ordinal', ignoreDuplicates: true })
    if (filesError) throw new Error('No fue posible guardar los archivos pendientes del respaldo.')
  }
  await updateProgress(admin, job, leaseToken, 'copying_attachments', await getFiles(admin, job.id), timings)
}

async function copyAttachmentBatch(admin: SupabaseClient, storage: Storage, job: Job, leaseToken: string): Promise<void> {
  const files = await getFiles(admin, job.id); const batch = nextPendingFiles(files, ATTACHMENTS_PER_INVOCATION).filter((file) => file.file_kind === 'attachment')
  if (batch.length === 0) { await updateProgress(admin, job, leaseToken, 'verifying', files, {}, { verification_cursor: 0 }); return }
  let downloadMs = 0; let uploadVerifyMs = 0
  for (const file of batch) {
    const downloadStarted = performance.now()
    const { data, error } = await admin.storage.from(file.source_bucket_id as string).download(file.source_name as string)
    downloadMs += performance.now() - downloadStarted
    if (error || !data) throw new Error('No fue posible descargar un adjunto privado para el respaldo.')
    const uploadStarted = performance.now()
    const verified = await putAndVerifyObject(storage, file.object_key, new Uint8Array(await data.arrayBuffer()), file.mime_type)
    uploadVerifyMs += performance.now() - uploadStarted
    const { error: fileError } = await admin.from('external_backup_job_files').update({ size_bytes: verified.sizeBytes, checksum_sha256: verified.sha256, status: 'verified', verified_at: new Date().toISOString(), failure_reason: null }).eq('id', file.id).eq('status', 'pending')
    if (fileError) throw new Error('No fue posible guardar la verificación del adjunto.')
  }
  await updateProgress(admin, job, leaseToken, 'copying_attachments', await getFiles(admin, job.id), { attachment_download: downloadMs, attachment_upload_and_verify: uploadVerifyMs })
}

async function verifyBatch(admin: SupabaseClient, storage: Storage, job: Job, leaseToken: string): Promise<void> {
  const files = await getFiles(admin, job.id)
  if (files.some((file) => file.status !== 'verified')) throw new Error('No se puede finalizar un respaldo con archivos sin verificar.')
  const batch = nextVerificationFiles(files, job.verification_cursor, VERIFICATIONS_PER_INVOCATION)
  const verificationStarted = performance.now()
  for (const file of batch) await verifyExistingObject(storage, file.object_key, file.size_bytes as number, file.checksum_sha256 as string)
  const nextCursor = job.verification_cursor + batch.length
  await updateProgress(admin, job, leaseToken, nextCursor >= files.length ? 'finalizing' : 'verifying', files, { final_head_verification: performance.now() - verificationStarted }, { verification_cursor: nextCursor })
}

async function finalizeJob(admin: SupabaseClient, storage: Storage, job: Job, leaseToken: string): Promise<void> {
  const files = await getFiles(admin, job.id)
  if (!canFinalize(files)) throw new Error('No se puede crear el manifiesto de un conjunto incompleto.')
  const { data: backupSet, error: setError } = await admin.from('external_backup_sets').select('storage_prefix, status').eq('id', job.backup_set_id).single()
  if (setError || !backupSet) throw new Error('No fue posible recuperar el conjunto de respaldo.')
  if (backupSet.status === 'valid') {
    await updateJob(admin, job, leaseToken, { status: 'completed', progress_percent: 100, error_message: null })
    return
  }
  if (!shouldFinalize(backupSet.status, files)) throw new Error('El conjunto no está disponible para una finalización única.')
  const manifestKey = `${backupSet.storage_prefix}/manifest.json`
  const manifest = { format: 'almacen-el-amigo-external-backup-v1', backup_set_id: job.backup_set_id, business_id: job.business_id, backup_kind: job.backup_kind, created_at: new Date().toISOString(), manifest_key: manifestKey, files: files.map((file) => ({ key: file.object_key, kind: file.file_kind, size_bytes: file.size_bytes, mime_type: file.mime_type, sha256: file.checksum_sha256, business_id: job.business_id, related_record: file.related_record, source: file.file_kind === 'attachment' ? { bucket_id: file.source_bucket_id, name: file.source_name } : undefined })) }
  const manifestStarted = performance.now()
  const verified = await putAndVerifyObject(storage, manifestKey, new TextEncoder().encode(`${JSON.stringify(manifest)}\n`), 'application/json')
  const { error: setUpdateError } = await admin.from('external_backup_sets').update({ status: 'valid', manifest, manifest_sha256: verified.sha256, verified_at: new Date().toISOString() }).eq('id', job.backup_set_id).eq('status', 'uploading')
  if (setUpdateError) throw new Error('No fue posible validar el conjunto externo.')
  const timing = { ...(job.timing_ms ?? {}), manifest_upload_and_verify: (job.timing_ms?.manifest_upload_and_verify ?? 0) + Math.round(performance.now() - manifestStarted) }
  await updateJob(admin, job, leaseToken, { status: 'completed', progress_percent: 100, timing_ms: timing, error_message: null })
}

async function processJob(admin: SupabaseClient, storage: Storage, jobId: string): Promise<Job | null> {
  const claimed = await claimJob(admin, jobId); if (!claimed) return null
  const { job, leaseToken } = claimed
  try {
    if (job.status === 'pending' || job.status === 'exporting') await prepareExports(admin, storage, job, leaseToken)
    else if (job.status === 'copying_attachments') await copyAttachmentBatch(admin, storage, job, leaseToken)
    else if (job.status === 'verifying') await verifyBatch(admin, storage, job, leaseToken)
    else if (job.status === 'finalizing') await finalizeJob(admin, storage, job, leaseToken)
  } catch (error) { await updateJob(admin, job, leaseToken, { status: 'failed', error_message: sanitizeBackupError(error), timing_ms: { ...(job.timing_ms ?? {}), failed_at_ms: Date.now() } }) }
  return getJob(admin, job.id)
}

async function retryJob(admin: SupabaseClient, job: Job): Promise<Job> {
  if (job.status !== 'failed') return job
  const files = await getFiles(admin, job.id)
  const failedFileIds = files.filter((file) => file.status === 'failed').map((file) => file.id)
  if (failedFileIds.length > 0) {
    const { error } = await admin.from('external_backup_job_files').update({ status: 'pending', failure_reason: null }).in('id', failedFileIds)
    if (error) throw new Error('No fue posible reanudar el respaldo.')
  }
  const resumedFiles = failedFileIds.length > 0 ? await getFiles(admin, job.id) : files
  const status = resumeStatus(resumedFiles) as JobStatus
  const verifiedFiles = resumedFiles.filter((file) => file.status === 'verified').length
  const verifiedAttachments = resumedFiles.filter((file) => file.status === 'verified' && file.file_kind === 'attachment').length
  const totalAttachments = resumedFiles.filter((file) => file.file_kind === 'attachment').length
  const { error } = await admin.from('external_backup_jobs').update({
    status,
    error_message: null,
    lease_token: null,
    lease_expires_at: null,
    verification_cursor: status === 'verifying' ? 0 : job.verification_cursor,
    total_files: resumedFiles.length,
    verified_files: verifiedFiles,
    total_attachments: totalAttachments,
    verified_attachments: verifiedAttachments,
    progress_percent: calculateProgress(resumedFiles.length, verifiedFiles, status),
  }).eq('id', job.id).eq('status', 'failed')
  if (error) throw new Error('No fue posible reanudar el respaldo.')
  return getJob(admin, job.id)
}

async function cleanupIncompleteJob(admin: SupabaseClient, storage: Storage): Promise<void> {
  const cutoff = new Date(Date.now() - INCOMPLETE_RETENTION_DAYS * 86_400_000).toISOString()
  const { data: jobs } = await admin.from('external_backup_jobs').select('*, external_backup_sets!inner(storage_prefix)').neq('status', 'completed').is('cleanup_completed_at', null).lt('created_at', cutoff).order('created_at').limit(1)
  const job = jobs?.[0] as (Job & { external_backup_sets: { storage_prefix: string } }) | undefined; if (!job) return
  const files = await getFiles(admin, job.id); const batch = files.filter((file) => file.cleanup_deleted_at === null).slice(0, VERIFICATIONS_PER_INVOCATION)
  for (const file of batch) { await storage.deleteObject(file.object_key); await admin.from('external_backup_job_files').update({ cleanup_deleted_at: new Date().toISOString() }).eq('id', file.id) }
  if (batch.length > 0) return
  for (const key of [`${job.external_backup_sets.storage_prefix}/data/backup-data.json`, `${job.external_backup_sets.storage_prefix}/exports/structured-export.json`, `${job.external_backup_sets.storage_prefix}/manifest.json`]) await storage.deleteObject(key)
  await admin.from('external_backup_jobs').update({ status: 'failed', error_message: 'Trabajo incompleto vencido; objetos parciales eliminados.', cleanup_completed_at: new Date().toISOString(), lease_token: null, lease_expires_at: null }).eq('id', job.id)
  await admin.from('external_backup_sets').update({ status: 'failed', failure_reason: 'Conjunto incompleto vencido; objetos parciales eliminados.' }).eq('id', job.backup_set_id).eq('status', 'uploading')
}

async function cleanupExpiredValidSet(admin: SupabaseClient, storage: Storage): Promise<void> {
  let { data: set } = await admin.from('external_backup_sets').select('id, storage_prefix').eq('status', 'deleting').order('created_at').limit(1).maybeSingle()
  if (!set) {
    const { data, error } = await admin.rpc('claim_expired_external_backup_set')
    if (error) throw new Error('No fue posible seleccionar la retención del respaldo.')
    set = Array.isArray(data) ? data[0] ?? null : data
  }
  if (!set) return
  const { data: job, error: jobError } = await admin.from('external_backup_jobs').select('id').eq('backup_set_id', set.id).eq('status', 'completed').maybeSingle()
  if (jobError || !job) throw new Error('No se puede eliminar un conjunto sin trabajo completo.')
  const files = await getFiles(admin, job.id)
  const batch = files.filter((file) => file.cleanup_deleted_at === null).slice(0, VERIFICATIONS_PER_INVOCATION)
  try {
    for (const file of batch) {
      await storage.deleteObject(file.object_key)
      const { error } = await admin.from('external_backup_job_files').update({ cleanup_deleted_at: new Date().toISOString() }).eq('id', file.id).is('cleanup_deleted_at', null)
      if (error) throw new Error('No fue posible guardar la limpieza del respaldo.')
    }
    if (batch.length > 0) return
    await storage.deleteObject(`${set.storage_prefix}/manifest.json`)
    const { error } = await admin.from('external_backup_sets').update({ status: 'deleted', deleted_at: new Date().toISOString() }).eq('id', set.id).eq('status', 'deleting')
    if (error) throw new Error('No fue posible terminar la retención del respaldo.')
  } catch {
    await admin.from('external_backup_sets').update({ status: 'deletion_failed', failure_reason: 'No fue posible eliminar de forma completa el conjunto vencido.' }).eq('id', set.id).eq('status', 'deleting')
    throw new Error('No fue posible limpiar el conjunto vencido.')
  }
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders }); if (request.method !== 'POST') return jsonResponse({ error: 'Método no permitido.' }, 405)
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL'); const anonKey = Deno.env.get('SUPABASE_ANON_KEY'); const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'); if (!supabaseUrl || !anonKey || !serviceRoleKey) throw new Error('El servidor no puede preparar el respaldo.')
    const { storage, jobToken } = readConfig(); const input = readRequest(await request.json() as BackupRequest); const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } }); const scheduled = constantTimeEqual(request.headers.get('x-backup-job-token') ?? '', jobToken)
    let userId: string | null = null
    if (!scheduled) { const authorization = request.headers.get('Authorization'); if (!authorization) return jsonResponse({ error: 'Tu sesión no es válida. Ingresa de nuevo.' }, 401); const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authorization } } }); const { data, error } = await userClient.auth.getUser(); if (error || !data.user) return jsonResponse({ error: 'Tu sesión no es válida. Ingresa de nuevo.' }, 401); userId = data.user.id }
    if (['start_automatic', 'process_pending', 'cleanup'].includes(input.action) && !scheduled) return jsonResponse({ error: 'La tarea automática requiere credenciales de servidor.' }, 401)
    if (input.action === 'start') { if (!input.businessId || !userId || !await isBusinessOwner(admin, input.businessId, userId)) return jsonResponse({ error: 'Solo el dueño puede iniciar el respaldo.' }, 403); return jsonResponse({ jobId: await startJob(admin, input.businessId, 'manual', userId), status: 'pending' }, 202) }
    if (input.action === 'status' || input.action === 'process' || input.action === 'retry') { if (!input.jobId) throw new Error('Indica el trabajo de respaldo.'); const job = await getJob(admin, input.jobId); if (!scheduled && (!userId || !await isBusinessOwner(admin, job.business_id, userId))) return jsonResponse({ error: 'No tienes permiso para este respaldo.' }, 403); const result = input.action === 'process' ? await processJob(admin, storage, job.id) : input.action === 'retry' ? await retryJob(admin, job) : job; return jsonResponse({ job: result ?? await getJob(admin, job.id) }, result?.status === 'completed' ? 200 : 202) }
    if (input.action === 'start_automatic') { if (!input.kind || input.kind === 'manual') throw new Error('Indica el tipo de respaldo automático.'); const { data: businesses, error } = await admin.from('businesses').select('id'); if (error || !businesses) throw new Error('No fue posible iniciar los respaldos automáticos.'); return jsonResponse({ jobIds: await Promise.all(businesses.map((business) => startJob(admin, business.id, input.kind as BackupKind, null))) }, 202) }
    if (input.action === 'process_pending') { const { data: jobs } = await admin.from('external_backup_jobs').select('id').in('status', ['pending', 'exporting', 'copying_attachments', 'verifying', 'finalizing']).order('created_at').limit(1); const job = jobs?.[0] ? await processJob(admin, storage, jobs[0].id) : null; return jsonResponse({ job }, job?.status === 'completed' || !job ? 200 : 202) }
    await cleanupIncompleteJob(admin, storage); await cleanupExpiredValidSet(admin, storage); return jsonResponse({ cleaned: true })
  } catch (error) { return jsonResponse({ error: sanitizeBackupError(error) }, 422) }
})
