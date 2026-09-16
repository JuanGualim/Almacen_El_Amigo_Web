export type CatalogAttributes = Record<string, string>

export function parseCatalogAttributes(value: string): CatalogAttributes {
  const attributes: CatalogAttributes = {}

  for (const line of value.split('\n')) {
    const normalizedLine = line.trim()

    if (!normalizedLine) {
      continue
    }

    const separatorIndex = normalizedLine.indexOf(':')
    if (separatorIndex <= 0) {
      throw new Error('Usa una línea por atributo con el formato Nombre: valor.')
    }

    const key = normalizedLine.slice(0, separatorIndex).trim().replace(/\s+/g, ' ').toLowerCase()
    const attributeValue = normalizedLine.slice(separatorIndex + 1).trim().replace(/\s+/g, ' ')

    if (!key || !attributeValue) {
      throw new Error('Cada atributo debe incluir un nombre y un valor.')
    }

    if (key.length > 60 || attributeValue.length > 120) {
      throw new Error('Un atributo es demasiado largo.')
    }

    if (Object.hasOwn(attributes, key)) {
      throw new Error(`El atributo “${key}” está repetido.`)
    }

    attributes[key] = attributeValue
  }

  return attributes
}

export function formatCatalogAttributes(attributes: CatalogAttributes): string {
  return Object.entries(attributes)
    .map(([key, value]) => `${key}: ${value}`)
    .join(' · ')
}
