const SHA256 = /^[0-9a-f]{64}$/

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

export function validateExternalBackupManifest(manifest) {
  assert(manifest && typeof manifest === 'object', 'El manifiesto no tiene un formato válido.')
  assert(manifest.format === 'almacen-el-amigo-external-backup-v1', 'El manifiesto no corresponde a un respaldo externo compatible.')
  assert(typeof manifest.backup_set_id === 'string' && manifest.backup_set_id.length > 0, 'El manifiesto no identifica el conjunto de respaldo.')
  assert(typeof manifest.business_id === 'string' && manifest.business_id.length > 0, 'El manifiesto no identifica el negocio.')
  assert(Array.isArray(manifest.files) && manifest.files.length >= 2, 'El manifiesto no contiene todos los archivos requeridos.')

  const keys = new Set()
  let dataFiles = 0
  let structuredExports = 0
  for (const file of manifest.files) {
    assert(file && typeof file === 'object', 'El manifiesto contiene una entrada de archivo inválida.')
    assert(['data', 'structured_export', 'attachment'].includes(file.kind), 'El manifiesto contiene un tipo de archivo inválido.')
    assert(typeof file.key === 'string' && file.key.length > 0 && !file.key.split('/').includes('..'), 'El manifiesto contiene una ruta de archivo inválida.')
    assert(!keys.has(file.key), 'El manifiesto contiene rutas duplicadas.')
    keys.add(file.key)
    assert(Number.isSafeInteger(file.size_bytes) && file.size_bytes >= 0, 'El manifiesto contiene un tamaño inválido.')
    assert(typeof file.mime_type === 'string' && file.mime_type.length > 0, 'El manifiesto contiene un MIME inválido.')
    assert(typeof file.sha256 === 'string' && SHA256.test(file.sha256), 'El manifiesto contiene un checksum inválido.')
    assert(file.business_id === manifest.business_id, 'Un archivo del manifiesto pertenece a otro negocio.')
    if (file.kind === 'data') dataFiles += 1
    if (file.kind === 'structured_export') structuredExports += 1
    if (file.kind === 'attachment') {
      assert(file.source && typeof file.source.bucket_id === 'string' && file.source.bucket_id.length > 0 && typeof file.source.name === 'string' && file.source.name.length > 0, 'Un adjunto no conserva su ruta original.')
    }
  }
  assert(dataFiles === 1 && structuredExports === 1, 'El manifiesto debe incluir exactamente datos y exportación JSON.')
  return manifest
}
