export const ATTACHMENTS_PER_INVOCATION = 1
export const VERIFICATIONS_PER_INVOCATION = 3

export function nextPendingFiles(files, limit) {
  return files.filter((file) => file.status === 'pending').slice(0, limit)
}

export function nextVerificationFiles(files, cursor, limit) {
  return files.filter((file) => file.status === 'verified').slice(cursor, cursor + limit)
}

export function calculateProgress(totalFiles, verifiedFiles, status) {
  if (status === 'completed') return 100
  if (totalFiles === 0) return status === 'pending' ? 0 : 5
  return Math.min(99, Math.round((verifiedFiles / totalFiles) * 90) + 5)
}

export function canFinalize(files) {
  return files.length > 0 && files.every((file) => file.status === 'verified')
}

export function resumeStatus(files) {
  if (files.length === 0 || files.some((file) => file.file_kind !== 'attachment' && file.status !== 'verified')) return 'exporting'
  if (files.some((file) => file.file_kind === 'attachment' && file.status !== 'verified')) return 'copying_attachments'
  return 'verifying'
}

export function sanitizeBackupError(error) {
  if (error && typeof error === 'object' && error.name === 'TimeoutError') return 'El proveedor externo no respondió a tiempo.'
  if (error instanceof Error && /checksum|verificaci.n remota/i.test(error.message)) return 'La verificación de integridad del objeto falló.'
  return 'No fue posible procesar el lote del respaldo externo.'
}
