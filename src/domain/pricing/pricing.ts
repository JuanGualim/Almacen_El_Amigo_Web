import type { Money } from '../money/money'

export function assertValidPriceRange(suggestedPrice: Money, minimumPrice: Money): void {
  if (suggestedPrice < 0 || minimumPrice < 0) {
    throw new Error('Los precios no pueden ser negativos.')
  }

  if (minimumPrice > suggestedPrice) {
    throw new Error('El precio mínimo no puede superar el precio sugerido.')
  }
}
