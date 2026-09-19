import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { getSupabaseClient } from '../../../services/api/supabaseClient'

type Conflict = { errorMessage: string; id: string; createdAt: string }

export function OfflineSaleConflictsPanel({ businessId }: { businessId: string }) {
  const [conflicts, setConflicts] = useState<Conflict[]>([])
  const [notes, setNotes] = useState<Record<string, string>>({})
  const [message, setMessage] = useState<string | null>(null)
  const load = useCallback(async () => {
    const { data, error } = await getSupabaseClient().from('offline_sale_sync_conflicts')
      .select('id, error_message, created_at').eq('business_id', businessId).eq('status', 'open').order('created_at', { ascending: false })
    if (error) { setMessage('No fue posible cargar los conflictos de ventas.'); return }
    setConflicts((data ?? []).map((row) => ({ id: row.id as string, errorMessage: row.error_message as string, createdAt: row.created_at as string })))
  }, [businessId])
  useEffect(() => { const timer = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(timer) }, [load])
  async function resolve(event: FormEvent<HTMLFormElement>, conflictId: string) {
    event.preventDefault()
    const resolutionNotes = notes[conflictId]?.trim() ?? ''
    if (resolutionNotes.length < 3) { setMessage('Indica cómo se resolvió el conflicto.'); return }
    const { error } = await getSupabaseClient().rpc('resolve_offline_sale_sync_conflict', { p_business_id: businessId, p_conflict_id: conflictId, p_resolution_notes: resolutionNotes })
    if (error) { setMessage('No fue posible resolver el conflicto.'); return }
    setMessage('Conflicto resuelto y auditado.'); await load()
  }
  if (conflicts.length === 0 && !message) return null
  return <section className="dashboard-pending" aria-labelledby="offline-conflicts-title">
    <h3 id="offline-conflicts-title">Conflictos de ventas pendientes</h3>
    {message ? <p className="notice" role="status">{message}</p> : null}
    {conflicts.length === 0 ? <p className="muted">No hay conflictos abiertos.</p> : <ul className="price-history-list">{conflicts.map((conflict) => <li key={conflict.id}><strong>{new Date(conflict.createdAt).toLocaleString('es-GT')}</strong><span>{conflict.errorMessage}</span><form onSubmit={(event) => void resolve(event, conflict.id)}><label className="field">Resolución<input value={notes[conflict.id] ?? ''} onChange={(event) => setNotes((current) => ({ ...current, [conflict.id]: event.target.value }))} minLength={3} maxLength={600} required /></label><button className="button button--compact">Marcar resuelto</button></form></li>)}</ul>}
  </section>
}
