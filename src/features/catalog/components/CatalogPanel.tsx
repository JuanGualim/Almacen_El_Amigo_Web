import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { parseCatalogAttributes } from '../../../domain/catalog/attributes'
import { formatGTQ, parseGTQ } from '../../../domain/money/money'
import {
  createCatalogProduct,
  createCatalogVariant,
  getCatalogVariants,
  getVariantPriceHistory,
  getVariantDescription,
  updateCatalogVariantPrices,
  type CatalogVariant,
  type VariantPriceHistoryEntry,
} from '../services/catalogService'

type CatalogPanelProps = {
  businessId: string
  canManage: boolean
}

type ProductForm = {
  attributes: string
  brandName: string
  categoryName: string
  minimumPrice: string
  productName: string
  suggestedPrice: string
}

const EMPTY_PRODUCT_FORM: ProductForm = {
  attributes: '',
  brandName: '',
  categoryName: '',
  minimumPrice: '',
  productName: '',
  suggestedPrice: '',
}

function toErrorMessage(error: unknown, fallback: string): string {
  return error instanceof Error ? error.message : fallback
}

export function CatalogPanel({ businessId, canManage }: CatalogPanelProps) {
  const [catalog, setCatalog] = useState<CatalogVariant[]>([])
  const [query, setQuery] = useState('')
  const [form, setForm] = useState<ProductForm>(EMPTY_PRODUCT_FORM)
  const [selectedVariant, setSelectedVariant] = useState<CatalogVariant | null>(null)
  const [priceHistory, setPriceHistory] = useState<VariantPriceHistoryEntry[]>([])
  const [variantAttributes, setVariantAttributes] = useState('')
  const [variantSuggestedPrice, setVariantSuggestedPrice] = useState('')
  const [variantMinimumPrice, setVariantMinimumPrice] = useState('')
  const [priceSuggested, setPriceSuggested] = useState('')
  const [priceMinimum, setPriceMinimum] = useState('')
  const [priceReason, setPriceReason] = useState('')
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [successMessage, setSuccessMessage] = useState<string | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [isLoadingPriceHistory, setIsLoadingPriceHistory] = useState(false)
  const [isSubmitting, setIsSubmitting] = useState(false)

  const loadCatalog = useCallback(async (nextQuery: string) => {
    try {
      setCatalog(await getCatalogVariants(businessId, nextQuery))
      setErrorMessage(null)
    } catch (error) {
      setErrorMessage(toErrorMessage(error, 'No fue posible cargar el catálogo.'))
    } finally {
      setIsLoading(false)
    }
  }, [businessId])

  useEffect(() => {
    const taskId = window.setTimeout(() => {
      void loadCatalog('')
    }, 0)

    return () => window.clearTimeout(taskId)
  }, [loadCatalog])

  function selectVariant(variant: CatalogVariant) {
    setSelectedVariant(variant)
    setVariantAttributes('')
    setVariantSuggestedPrice(variant.suggestedPrice !== null ? String(variant.suggestedPrice / 100) : '')
    setVariantMinimumPrice(variant.minimumPrice !== null ? String(variant.minimumPrice / 100) : '')
    setPriceSuggested(variant.suggestedPrice !== null ? String(variant.suggestedPrice / 100) : '')
    setPriceMinimum(variant.minimumPrice !== null ? String(variant.minimumPrice / 100) : '')
    setPriceReason('')
    setPriceHistory([])
    setErrorMessage(null)
    setSuccessMessage(null)
    void loadPriceHistory(variant.variantId)
  }

  async function loadPriceHistory(variantId: string) {
    setIsLoadingPriceHistory(true)

    try {
      setPriceHistory(await getVariantPriceHistory(variantId))
    } catch (error) {
      setErrorMessage(toErrorMessage(error, 'No fue posible cargar el historial de precios.'))
    } finally {
      setIsLoadingPriceHistory(false)
    }
  }

  async function handleSearch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setIsLoading(true)
    await loadCatalog(query)
  }

  async function handleCreateProduct(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setErrorMessage(null)
    setSuccessMessage(null)
    setIsSubmitting(true)

    try {
      await createCatalogProduct(businessId, {
        attributes: parseCatalogAttributes(form.attributes),
        brandName: form.brandName,
        categoryName: form.categoryName,
        minimumPrice: parseGTQ(form.minimumPrice),
        productName: form.productName,
        suggestedPrice: parseGTQ(form.suggestedPrice),
      })
      setForm(EMPTY_PRODUCT_FORM)
      setSuccessMessage('Producto y primera variante creados correctamente.')
      await loadCatalog('')
    } catch (error) {
      setErrorMessage(toErrorMessage(error, 'No fue posible crear el producto.'))
    } finally {
      setIsSubmitting(false)
    }
  }

  async function handleCreateVariant(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!selectedVariant) {
      return
    }

    setErrorMessage(null)
    setSuccessMessage(null)
    setIsSubmitting(true)

    try {
      await createCatalogVariant(
        businessId,
        selectedVariant.productId,
        parseCatalogAttributes(variantAttributes),
        parseGTQ(variantSuggestedPrice),
        parseGTQ(variantMinimumPrice),
      )
      setSuccessMessage('Nueva variante creada correctamente.')
      await loadCatalog(query)
    } catch (error) {
      setErrorMessage(toErrorMessage(error, 'No fue posible crear la variante.'))
    } finally {
      setIsSubmitting(false)
    }
  }

  async function handleUpdatePrices(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!selectedVariant) {
      return
    }

    if (priceReason.trim().length < 3) {
      setErrorMessage('Indica un motivo de al menos tres caracteres para el cambio de precio.')
      return
    }

    setErrorMessage(null)
    setSuccessMessage(null)
    setIsSubmitting(true)

    try {
      await updateCatalogVariantPrices(
        businessId,
        selectedVariant.variantId,
        parseGTQ(priceSuggested),
        parseGTQ(priceMinimum),
        priceReason,
      )
      setSuccessMessage('Precios actualizados; el cambio quedó en el historial.')
      await loadCatalog(query)
    } catch (error) {
      setErrorMessage(toErrorMessage(error, 'No fue posible actualizar los precios.'))
    } finally {
      setIsSubmitting(false)
    }
  }

  return (
    <section className="catalog-panel" aria-labelledby="catalog-title">
      <h2 id="catalog-title">Catálogo</h2>
      <p className="muted">Busca productos, variantes y precios vigentes del negocio activo.</p>

      <form className="catalog-search" onSubmit={handleSearch}>
        <label className="field" htmlFor="catalog-query">
          Buscar por nombre, código o atributo
          <input
            id="catalog-query"
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Ej. camisa, blanca, 15 o ALM-"
            value={query}
          />
        </label>
        <button className="button button--compact" type="submit">Buscar</button>
      </form>

      {canManage ? (
        <form className="catalog-form" onSubmit={handleCreateProduct}>
          <h3>Crear producto y primera variante</h3>
          <label className="field" htmlFor="catalog-category">
            Categoría
            <input
              id="catalog-category"
              maxLength={120}
              onChange={(event) => setForm({ ...form, categoryName: event.target.value })}
              placeholder="Ej. Camisas"
              required
              value={form.categoryName}
            />
          </label>
          <label className="field" htmlFor="catalog-product-name">
            Producto o modelo
            <input
              id="catalog-product-name"
              maxLength={180}
              onChange={(event) => setForm({ ...form, productName: event.target.value })}
              placeholder="Ej. Camisa lisa de manga larga"
              required
              value={form.productName}
            />
          </label>
          <label className="field" htmlFor="catalog-brand">
            Marca (opcional)
            <input
              id="catalog-brand"
              maxLength={120}
              onChange={(event) => setForm({ ...form, brandName: event.target.value })}
              placeholder="Ej. Manhattan"
              value={form.brandName}
            />
          </label>
          <label className="field" htmlFor="catalog-attributes">
            Atributos de la primera variante (opcional)
            <textarea
              id="catalog-attributes"
              onChange={(event) => setForm({ ...form, attributes: event.target.value })}
              placeholder={'Color: Blanca\nTalla: 15'}
              value={form.attributes}
            />
          </label>
          <div className="catalog-price-fields">
            <label className="field" htmlFor="catalog-suggested-price">
              Precio sugerido
              <input
                id="catalog-suggested-price"
                inputMode="decimal"
                onChange={(event) => setForm({ ...form, suggestedPrice: event.target.value })}
                placeholder="185.00"
                required
                value={form.suggestedPrice}
              />
            </label>
            <label className="field" htmlFor="catalog-minimum-price">
              Precio mínimo
              <input
                id="catalog-minimum-price"
                inputMode="decimal"
                onChange={(event) => setForm({ ...form, minimumPrice: event.target.value })}
                placeholder="160.00"
                required
                value={form.minimumPrice}
              />
            </label>
          </div>
          <button className="button" disabled={isSubmitting} type="submit">
            {isSubmitting ? 'Guardando…' : 'Crear producto'}
          </button>
        </form>
      ) : null}

      {successMessage ? <p className="notice notice--success" role="status">{successMessage}</p> : null}
      {errorMessage ? <p className="notice" role="alert">{errorMessage}</p> : null}

      <h3>Variantes disponibles</h3>
      {isLoading ? <p className="muted">Cargando catálogo…</p> : null}
      {!isLoading && catalog.length === 0 ? (
        <p className="muted">No hay variantes que coincidan. Aún no se registra inventario en esta fase.</p>
      ) : null}
      {!isLoading && catalog.length > 0 ? (
        <ul className="catalog-list">
          {catalog.map((variant) => (
            <li key={variant.variantId}>
              <button
                className="catalog-card"
                onClick={() => selectVariant(variant)}
                type="button"
              >
                <strong>{variant.productName}</strong>
                <span className="muted">{variant.brandName ?? variant.categoryName} · {getVariantDescription(variant)}</span>
                <span className="muted">{variant.variantCode}</span>
                {variant.suggestedPrice !== null && variant.minimumPrice !== null ? (
                  <span>Precio: {formatGTQ(variant.suggestedPrice)} · Mín.: {formatGTQ(variant.minimumPrice)}</span>
                ) : <span className="muted">No tienes permiso para ver precios.</span>}
              </button>
            </li>
          ))}
        </ul>
      ) : null}

      {canManage && selectedVariant ? (
        <section className="catalog-editor" aria-labelledby="catalog-editor-title">
          <h3 id="catalog-editor-title">Gestionar {selectedVariant.productName}</h3>
          <p className="muted">Variante seleccionada: {selectedVariant.variantCode}</p>

          <form className="catalog-form" onSubmit={handleCreateVariant}>
            <h4>Agregar otra variante</h4>
            <label className="field" htmlFor="new-variant-attributes">
              Atributos
              <textarea
                id="new-variant-attributes"
                onChange={(event) => setVariantAttributes(event.target.value)}
                placeholder={'Color: Azul\nTalla: 15'}
                value={variantAttributes}
              />
            </label>
            <div className="catalog-price-fields">
              <label className="field" htmlFor="new-variant-suggested">
                Precio sugerido
                <input
                  id="new-variant-suggested"
                  inputMode="decimal"
                  onChange={(event) => setVariantSuggestedPrice(event.target.value)}
                  required
                  value={variantSuggestedPrice}
                />
              </label>
              <label className="field" htmlFor="new-variant-minimum">
                Precio mínimo
                <input
                  id="new-variant-minimum"
                  inputMode="decimal"
                  onChange={(event) => setVariantMinimumPrice(event.target.value)}
                  required
                  value={variantMinimumPrice}
                />
              </label>
            </div>
            <button className="button button--compact" disabled={isSubmitting} type="submit">
              Crear variante
            </button>
          </form>

          <form className="catalog-form" onSubmit={handleUpdatePrices}>
            <h4>Actualizar precios</h4>
            <div className="catalog-price-fields">
              <label className="field" htmlFor="update-suggested-price">
                Precio sugerido
                <input
                  id="update-suggested-price"
                  inputMode="decimal"
                  onChange={(event) => setPriceSuggested(event.target.value)}
                  required
                  value={priceSuggested}
                />
              </label>
              <label className="field" htmlFor="update-minimum-price">
                Precio mínimo
                <input
                  id="update-minimum-price"
                  inputMode="decimal"
                  onChange={(event) => setPriceMinimum(event.target.value)}
                  required
                  value={priceMinimum}
                />
              </label>
            </div>
            <label className="field" htmlFor="price-reason">
              Motivo del cambio
              <input
                id="price-reason"
                maxLength={300}
                minLength={3}
                onChange={(event) => setPriceReason(event.target.value)}
                required
                value={priceReason}
              />
            </label>
            <button className="button button--compact" disabled={isSubmitting} type="submit">
              Actualizar precios
            </button>
          </form>
        </section>
      ) : null}

      {selectedVariant && selectedVariant.suggestedPrice !== null ? (
        <section className="catalog-price-history" aria-labelledby="price-history-title">
          <h3 id="price-history-title">Historial de precios</h3>
          {isLoadingPriceHistory ? <p className="muted">Cargando historial…</p> : null}
          {!isLoadingPriceHistory && priceHistory.length === 0 ? (
            <p className="muted">No hay cambios de precio registrados.</p>
          ) : null}
          {!isLoadingPriceHistory && priceHistory.length > 0 ? (
            <ul className="price-history-list">
              {priceHistory.map((entry, index) => (
                <li key={`${entry.changedAt}-${entry.kind}-${index}`}>
                  <strong>{entry.kind === 'suggested' ? 'Precio sugerido' : 'Precio mínimo'}: {formatGTQ(entry.amount)}</strong>
                  <span className="muted">
                    {new Intl.DateTimeFormat('es-GT', {
                      dateStyle: 'medium',
                      timeStyle: 'short',
                    }).format(new Date(entry.changedAt))}
                    {entry.reason ? ` · ${entry.reason}` : ''}
                  </span>
                </li>
              ))}
            </ul>
          ) : null}
        </section>
      ) : null}
    </section>
  )
}
