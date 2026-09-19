import type { CashRegisterSummary } from '../../cash-register/services/cashRegisterService'
import type { Money } from '../../../domain/money/money'
import type { SaleLineInput, SalePaymentMethod, SellableVariant } from './salesService'

const DATABASE_NAME = 'almacen-el-amigo-offline'
const DATABASE_VERSION = 1
const SALES_STORE = 'sales'
const SNAPSHOTS_STORE = 'snapshots'
const DRAFTS_STORE = 'drafts'

export type OfflineSaleStatus = 'pending' | 'syncing' | 'confirmed' | 'conflict'
export type OfflineSale = {
  businessId: string
  cashSessionId: string
  createdAt: string
  errorMessage: string | null
  lines: SaleLineInput[]
  paymentMethod: SalePaymentMethod
  requestId: string
  status: OfflineSaleStatus
  userId: string
}

export type OfflineSaleDraft = {
  lines: Array<SaleLineInput & { description: string; minimumPrice: Money }>
  paymentMethod: SalePaymentMethod
}

type SalesSnapshot = { cashSummary: CashRegisterSummary | null; variants: SellableVariant[] }
type StoredValue<T> = { id: string; value: T }

function key(userId: string, businessId: string, suffix: string): string {
  return `${userId}:${businessId}:${suffix}`
}

function database(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE_NAME, DATABASE_VERSION)
    request.onerror = () => reject(new Error('No fue posible abrir el almacenamiento local.'))
    request.onupgradeneeded = () => {
      const db = request.result
      for (const store of [SALES_STORE, SNAPSHOTS_STORE, DRAFTS_STORE]) {
        if (!db.objectStoreNames.contains(store)) db.createObjectStore(store, { keyPath: 'id' })
      }
    }
    request.onsuccess = () => resolve(request.result)
  })
}

async function put<T>(storeName: string, id: string, value: T): Promise<void> {
  const db = await database()
  await new Promise<void>((resolve, reject) => {
    const transaction = db.transaction(storeName, 'readwrite')
    transaction.objectStore(storeName).put({ id, value } satisfies StoredValue<T>)
    transaction.onerror = () => reject(new Error('No fue posible guardar los datos locales.'))
    transaction.oncomplete = () => resolve()
  })
  db.close()
}

async function get<T>(storeName: string, id: string): Promise<T | null> {
  const db = await database()
  const value = await new Promise<T | null>((resolve, reject) => {
    const request = db.transaction(storeName, 'readonly').objectStore(storeName).get(id)
    request.onerror = () => reject(new Error('No fue posible leer los datos locales.'))
    request.onsuccess = () => resolve((request.result as StoredValue<T> | undefined)?.value ?? null)
  })
  db.close()
  return value
}

export async function cacheSalesSnapshot(userId: string, businessId: string, snapshot: SalesSnapshot): Promise<void> {
  await put(SNAPSHOTS_STORE, key(userId, businessId, 'sales'), snapshot)
}

export async function getCachedSalesSnapshot(userId: string, businessId: string): Promise<SalesSnapshot | null> {
  return get<SalesSnapshot>(SNAPSHOTS_STORE, key(userId, businessId, 'sales'))
}

export async function saveOfflineSaleDraft(userId: string, businessId: string, draft: OfflineSaleDraft): Promise<void> {
  await put(DRAFTS_STORE, key(userId, businessId, 'sale-draft'), draft)
}

export async function getOfflineSaleDraft(userId: string, businessId: string): Promise<OfflineSaleDraft | null> {
  return get<OfflineSaleDraft>(DRAFTS_STORE, key(userId, businessId, 'sale-draft'))
}

export async function clearOfflineSaleDraft(userId: string, businessId: string): Promise<void> {
  const db = await database()
  await new Promise<void>((resolve, reject) => {
    const request = db.transaction(DRAFTS_STORE, 'readwrite').objectStore(DRAFTS_STORE).delete(key(userId, businessId, 'sale-draft'))
    request.onerror = () => reject(new Error('No fue posible eliminar el borrador local.'))
    request.onsuccess = () => resolve()
  })
  db.close()
}

export async function saveOfflineSale(sale: OfflineSale): Promise<void> {
  await put(SALES_STORE, key(sale.userId, sale.businessId, sale.requestId), sale)
}

export async function getOfflineSales(userId: string, businessId: string): Promise<OfflineSale[]> {
  const db = await database()
  const values = await new Promise<OfflineSale[]>((resolve, reject) => {
    const request = db.transaction(SALES_STORE, 'readonly').objectStore(SALES_STORE).getAll()
    request.onerror = () => reject(new Error('No fue posible leer las ventas pendientes.'))
    request.onsuccess = () => resolve((request.result as StoredValue<OfflineSale>[])
      .map((item) => item.value)
      .filter((sale) => sale.userId === userId && sale.businessId === businessId)
      .sort((first, second) => second.createdAt.localeCompare(first.createdAt)))
  })
  db.close()
  return values
}

export async function updateOfflineSale(sale: OfflineSale): Promise<void> {
  await saveOfflineSale(sale)
}

export async function clearOfflineDataForUser(userId: string): Promise<void> {
  const db = await database()
  for (const storeName of [SALES_STORE, SNAPSHOTS_STORE, DRAFTS_STORE]) {
    const items = await new Promise<StoredValue<unknown>[]>((resolve, reject) => {
      const request = db.transaction(storeName, 'readonly').objectStore(storeName).getAll()
      request.onerror = () => reject(new Error('No fue posible limpiar los datos locales.'))
      request.onsuccess = () => resolve(request.result as StoredValue<unknown>[])
    })
    await new Promise<void>((resolve, reject) => {
      const transaction = db.transaction(storeName, 'readwrite')
      for (const item of items) if (item.id.startsWith(`${userId}:`)) transaction.objectStore(storeName).delete(item.id)
      transaction.onerror = () => reject(new Error('No fue posible limpiar los datos locales.'))
      transaction.oncomplete = () => resolve()
    })
  }
  db.close()
}
