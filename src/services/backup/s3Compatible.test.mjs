import { describe, expect, it } from 'vitest'
import { putAndVerifyObject, sha256Hex, verifyExistingObject } from '../../../supabase/functions/_shared/s3-compatible.mjs'

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

  it('accepts an S3 provider with inaccurate HEAD length when downloaded bytes match', async () => {
    const storage = {
      async putObject() {},
      async headObject() { return { contentLength: 3, contentType: 'application/json', sha256: '0'.repeat(64) } },
      async getObject() { return new Response('ok') },
      async deleteObject() {},
    }
    await expect(putAndVerifyObject(storage, 'sets/test/data.json', new TextEncoder().encode('ok'), 'application/json')).resolves.toMatchObject({ sizeBytes: 2 })
  })

  it('accepts an S3 provider that omits custom metadata but returns matching bytes', async () => {
    const body = new TextEncoder().encode('ok')
    const storage = {
      async putObject() {},
      async headObject() { return { contentLength: body.byteLength, contentType: 'application/json', sha256: null } },
      async getObject() { return new Response(body) },
      async deleteObject() {},
    }
    await expect(putAndVerifyObject(storage, 'sets/test/data.json', body, 'application/json')).resolves.toEqual({ sizeBytes: 2, sha256: await sha256Hex(body) })
  })

  it('accepts transformed custom metadata when downloaded bytes still match', async () => {
    const body = new TextEncoder().encode('ok')
    const storage = {
      async putObject() {},
      async headObject() { return { contentLength: body.byteLength, contentType: 'application/json', sha256: 'provider-specific-value' } },
      async getObject() { return new Response(body) },
      async deleteObject() {},
    }
    await expect(putAndVerifyObject(storage, 'sets/test/data.json', body, 'application/json')).resolves.toEqual({ sizeBytes: 2, sha256: await sha256Hex(body) })
  })

  it('recalculates checksum during final verification when HEAD has no metadata', async () => {
    const body = new TextEncoder().encode('verified')
    const storage = {
      async headObject() { return { contentLength: body.byteLength, contentType: 'application/json', sha256: null } },
      async getObject() { return new Response(body) },
    }
    await expect(verifyExistingObject(storage, 'sets/test/data.json', body.byteLength, await sha256Hex(body))).resolves.toBeUndefined()
  })

  it('still rejects altered downloaded bytes when custom metadata is absent', async () => {
    const expected = new TextEncoder().encode('expected')
    const storage = {
      async headObject() { return { contentLength: expected.byteLength, contentType: 'application/json', sha256: null } },
      async getObject() { return new Response('altered!') },
    }
    await expect(verifyExistingObject(storage, 'sets/test/data.json', expected.byteLength, await sha256Hex(expected))).rejects.toThrow('checksum')
  })

  it('rejects a downloaded object whose actual size differs', async () => {
    const expected = new TextEncoder().encode('expected')
    const storage = {
      async headObject() { return { contentLength: 0, contentType: 'application/json', sha256: null } },
      async getObject() { return new Response('short') },
    }
    await expect(verifyExistingObject(storage, 'sets/test/data.json', expected.byteLength, await sha256Hex(expected))).rejects.toThrow('tamaño descargado')
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
