import { describe, expect, it } from 'vitest'
import { putAndVerifyObject, sha256Hex } from '../../../supabase/functions/_shared/s3-compatible.mjs'

describe('S3 compatible backup verification', () => {
  it('requires matching remote size and checksum after upload', async () => {
    const objects = new Map()
    const storage = {
      async putObject(key, body) { objects.set(key, body) },
      async headObject(key) {
        const body = objects.get(key)
        return body ? { contentLength: body.byteLength, contentType: 'application/json', sha256: await sha256Hex(body) } : null
      },
      async getObject(key) { return new Response(objects.get(key)) },
      async deleteObject() {},
    }
    const body = new TextEncoder().encode('{"backup":true}\n')

    await expect(putAndVerifyObject(storage, 'sets/test/data.json', body, 'application/json')).resolves.toEqual({
      sizeBytes: body.byteLength,
      sha256: await sha256Hex(body),
    })
  })

  it('rejects an object when its returned bytes differ from its checksum', async () => {
    const storage = {
      async putObject() {},
      async headObject() { return { contentLength: 2, contentType: 'application/json', sha256: '0'.repeat(64) } },
      async getObject() { return new Response('ok') },
      async deleteObject() {},
    }
    await expect(putAndVerifyObject(storage, 'sets/test/data.json', new TextEncoder().encode('ok'), 'application/json')).rejects.toThrow('cabecera')
  })

  it('propagates a provider failure without treating the object as verified', async () => {
    const storage = {
      async putObject() { throw new Error('provider unavailable') },
      async headObject() { throw new Error('should not verify') },
      async getObject() { throw new Error('should not read') },
      async deleteObject() {},
    }
    await expect(putAndVerifyObject(storage, 'sets/test/data.json', new TextEncoder().encode('ok'), 'application/json')).rejects.toThrow('provider unavailable')
  })
})
