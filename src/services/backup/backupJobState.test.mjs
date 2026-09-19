import { describe, expect, it } from 'vitest'
import { ATTACHMENTS_PER_INVOCATION, canFinalize, nextPendingFiles, resumeStatus, sanitizeBackupError } from '../../../supabase/functions/_shared/backup-job-state.mjs'

const pending = (ordinal) => ({ ordinal, file_kind: 'attachment', status: 'pending' })
const verified = (ordinal) => ({ ordinal, file_kind: 'attachment', status: 'verified' })

describe('external backup batch checkpoints', () => {
  it('terminates a batch before the next attachment and resumes at that attachment', () => {
    const files = [verified(0), pending(1), pending(2)]
    expect(ATTACHMENTS_PER_INVOCATION).toBe(1)
    expect(nextPendingFiles(files, ATTACHMENTS_PER_INVOCATION).map((file) => file.ordinal)).toEqual([1])

    files[1].status = 'verified'
    expect(nextPendingFiles(files, ATTACHMENTS_PER_INVOCATION).map((file) => file.ordinal)).toEqual([2])
  })

  it('does not schedule an already copied file in a duplicate invocation', () => {
    expect(nextPendingFiles([verified(0), pending(1)], 1).map((file) => file.ordinal)).toEqual([1])
  })

  it('continues a failed job from its unverified attachment rather than exporting again', () => {
    expect(resumeStatus([{ file_kind: 'data', status: 'verified' }, { file_kind: 'structured_export', status: 'verified' }, pending(2)])).toBe('copying_attachments')
  })

  it('permits finalization exactly once all files are verified', () => {
    expect(canFinalize([verified(0), pending(1)])).toBe(false)
    expect(canFinalize([verified(0), verified(1)])).toBe(true)
    expect(canFinalize([])).toBe(false)
  })

  it('returns a sanitized provider error without source details', () => {
    expect(sanitizeBackupError(new Error('R2 endpoint https://private.example/secret failed'))).toBe('No fue posible procesar el lote del respaldo externo.')
  })
})
