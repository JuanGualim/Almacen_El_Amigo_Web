const textEncoder = new TextEncoder()

function hex(bytes) {
  return Array.from(new Uint8Array(bytes), (byte) => byte.toString(16).padStart(2, '0')).join('')
}

export async function sha256Hex(bytes) {
  return hex(await crypto.subtle.digest('SHA-256', bytes))
}

async function hmac(key, value) {
  const cryptoKey = await crypto.subtle.importKey('raw', key, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  return new Uint8Array(await crypto.subtle.sign('HMAC', cryptoKey, textEncoder.encode(value)))
}

function encodeKey(key) {
  return key.split('/').map((segment) => encodeURIComponent(segment)).join('/')
}

function awsTimestamp(date) {
  const value = date.toISOString().replace(/[:-]|\.\d{3}/g, '')
  return { dateStamp: value.slice(0, 8), timestamp: value }
}

async function signingKey(secret, dateStamp, region) {
  const dateKey = await hmac(textEncoder.encode(`AWS4${secret}`), dateStamp)
  const regionKey = await hmac(dateKey, region)
  const serviceKey = await hmac(regionKey, 's3')
  return hmac(serviceKey, 'aws4_request')
}

export function createS3CompatibleStorage(config) {
  const endpoint = new URL(config.endpoint)
  const region = config.region ?? 'auto'

  async function request(method, key, body, contentType, checksum) {
    const { dateStamp, timestamp } = awsTimestamp(new Date())
    const payloadHash = body ? await sha256Hex(body) : await sha256Hex(new Uint8Array())
    const url = new URL(`/${encodeURIComponent(config.bucket)}/${encodeKey(key)}`, endpoint)
    const headers = new Headers({ host: endpoint.host, 'x-amz-content-sha256': payloadHash, 'x-amz-date': timestamp })
    if (contentType) headers.set('content-type', contentType)
    if (checksum) headers.set('x-amz-meta-sha256', checksum)
    const canonicalHeaders = Array.from(headers.entries()).sort(([left], [right]) => left.localeCompare(right)).map(([name, value]) => `${name}:${value.trim()}\n`).join('')
    const signedHeaders = Array.from(headers.keys()).sort().join(';')
    const canonicalRequest = [method, url.pathname, '', canonicalHeaders, signedHeaders, payloadHash].join('\n')
    const credentialScope = `${dateStamp}/${region}/s3/aws4_request`
    const stringToSign = ['AWS4-HMAC-SHA256', timestamp, credentialScope, await sha256Hex(textEncoder.encode(canonicalRequest))].join('\n')
    const signature = hex(await hmac(await signingKey(config.secretAccessKey, dateStamp, region), stringToSign))
    headers.set('authorization', `AWS4-HMAC-SHA256 Credential=${config.accessKeyId}/${credentialScope}, SignedHeaders=${signedHeaders}, Signature=${signature}`)
    return fetch(url, { method, headers, body, signal: globalThis.AbortSignal.timeout(30_000) })
  }

  return {
    async putObject(key, body, contentType, checksum) {
      const response = await request('PUT', key, body, contentType, checksum)
      if (!response.ok) throw new Error(`No fue posible escribir el objeto externo (${response.status}).`)
    },
    async getObject(key) {
      const response = await request('GET', key)
      if (!response.ok) throw new Error(`No fue posible leer el objeto externo (${response.status}).`)
      return response
    },
    async headObject(key) {
      const response = await request('HEAD', key)
      if (response.status === 404) return null
      if (!response.ok) throw new Error(`No fue posible verificar el objeto externo (${response.status}).`)
      const contentLength = Number(response.headers.get('content-length'))
      if (!Number.isSafeInteger(contentLength) || contentLength < 0) throw new Error('El almacenamiento externo devolvió un tamaño inválido.')
      return { contentLength, contentType: response.headers.get('content-type'), sha256: response.headers.get('x-amz-meta-sha256') }
    },
    async deleteObject(key) {
      const response = await request('DELETE', key)
      if (!response.ok && response.status !== 404) throw new Error(`No fue posible eliminar el objeto externo (${response.status}).`)
    },
  }
}

export async function putAndVerifyObject(storage, key, body, contentType) {
  const sha256 = await sha256Hex(body)
  await storage.putObject(key, body, contentType, sha256)
  const head = await storage.headObject(key)
  if (!head || head.contentLength !== body.byteLength || head.sha256 !== sha256) throw new Error('La verificación remota por cabecera no coincidió.')
  const verifiedBody = new Uint8Array(await (await storage.getObject(key)).arrayBuffer())
  if (verifiedBody.byteLength !== body.byteLength || await sha256Hex(verifiedBody) !== sha256) throw new Error('La verificación remota del checksum no coincidió.')
  return { sizeBytes: body.byteLength, sha256 }
}
