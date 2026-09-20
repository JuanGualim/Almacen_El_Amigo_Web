import { describe, expect, it } from 'vitest'
import { validateExternalBackupManifest } from '../../../scripts/backup/backup-manifest.mjs'

function manifest() {
  return {
    format: 'almacen-el-amigo-external-backup-v1', backup_set_id: 'set-1', business_id: 'business-1',
    files: [
      { kind: 'data', key: 'set/data/backup-data.json', size_bytes: 2, mime_type: 'application/json', sha256: 'a'.repeat(64), business_id: 'business-1', related_record: null },
      { kind: 'structured_export', key: 'set/exports/structured.json', size_bytes: 2, mime_type: 'application/json', sha256: 'b'.repeat(64), business_id: 'business-1', related_record: null },
      { kind: 'attachment', key: 'set/attachments/file.pdf', size_bytes: 2, mime_type: 'application/pdf', sha256: 'c'.repeat(64), business_id: 'business-1', related_record: 'record-1', source: { bucket_id: 'invoices', name: 'file.pdf' } },
    ],
  }
}

describe('external backup manifest validation', () => {
  it('accepts a complete manifest before a restore writes anything', () => {
    expect(validateExternalBackupManifest(manifest())).toMatchObject({ backup_set_id: 'set-1' })
  })

  it('rejects a mismatched checksum before restoration', () => {
    const invalid = manifest()
    invalid.files[2].sha256 = 'not-a-checksum'
    expect(() => validateExternalBackupManifest(invalid)).toThrow('checksum')
  })

  it('rejects an attachment with a missing original path', () => {
    const invalid = manifest()
    delete invalid.files[2].source
    expect(() => validateExternalBackupManifest(invalid)).toThrow('ruta original')
  })
})
