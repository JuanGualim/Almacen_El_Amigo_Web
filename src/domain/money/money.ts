export type Money = number & { readonly __brand: 'MoneyInMinorUnits' }

const GTQ_FRACTION_DIGITS = 2

export function moneyFromMinorUnits(value: number): Money {
  if (!Number.isSafeInteger(value)) {
    throw new Error('El importe debe ser un entero seguro de unidades mínimas.')
  }

  return value as Money
}

export function parseGTQ(value: string): Money {
  const normalized = value.trim().replace(/^Q\s*/, '').replace(/,/g, '')
  const match = /^(-?)(\d+)(?:\.(\d{1,2}))?$/.exec(normalized)

  if (!match) {
    throw new Error('Ingresa un importe válido con hasta dos decimales.')
  }

  const [, sign, whole, fraction = ''] = match
  const minorUnits = Number(whole) * 100 + Number(fraction.padEnd(GTQ_FRACTION_DIGITS, '0'))

  return moneyFromMinorUnits(sign === '-' ? -minorUnits : minorUnits)
}

export function formatGTQ(value: Money): string {
  return new Intl.NumberFormat('es-GT', {
    style: 'currency',
    currency: 'GTQ',
    minimumFractionDigits: GTQ_FRACTION_DIGITS,
    maximumFractionDigits: GTQ_FRACTION_DIGITS,
  }).format(value / 100)
}

export function serializeGTQ(value: Money): string {
  const absoluteValue = Math.abs(value)
  const whole = Math.trunc(absoluteValue / 100)
  const fraction = String(absoluteValue % 100).padStart(GTQ_FRACTION_DIGITS, '0')

  return `${value < 0 ? '-' : ''}${whole}.${fraction}`
}

export function addMoney(...values: Money[]): Money {
  return moneyFromMinorUnits(values.reduce((sum, value) => sum + value, 0))
}
