import { useEffect, useState } from 'react'
import { api, type LibraryRow, type PublishedRow } from './api'
import { ErrorText, ReviewBadge, useAction } from './ui'

/** Published scenarios, to launch by code or to copy into your own library.
 *  shortcut: lists what is published on this server only, no accounts, ratings or payment;
 *  point it at a shared catalogue service when scenarios should travel between sites. */
export default function Marketplace({ visible, version, onDownloaded }: { visible: boolean; version: number; onDownloaded: (id: string) => void }) {
  const [items, setItems] = useState<PublishedRow[] | null>(null)
  const [library, setLibrary] = useState<LibraryRow[]>([])
  const [query, setQuery] = useState('')
  const [onlyReviewed, setOnlyReviewed] = useState(false)
  const load = useAction()
  const get = useAction()
  useEffect(() => {
    if (!visible) return
    void load.run(async () => {
      const [p, l] = await Promise.all([api.published(), api.library()])
      setItems(p); setLibrary(l)
    })
  }, [visible, version, load.run])

  const q = query.trim().toLowerCase()
  const shown = (items ?? []).filter(s => (!onlyReviewed || s.review_state === 'clinician_reviewed')
    && (!q || [s.title, s.description, s.environment, s.difficulty, s.code].some(t => t.toLowerCase().includes(q))))

  return (
    <div>
      <div className="head-row"><h2>Scenario marketplace</h2></div>
      <p className="muted">Published scenarios on this server. Launch one in the MedSim XR app with its code, or download a copy to adapt.
        A copy arrives as a draft in <em>Downloaded</em>; the original's review state does not carry over.</p>
      <div className="row filters">
        <label className="field"><span>Search</span><input value={query} onChange={e => setQuery(e.target.value)} placeholder="Title, setting, difficulty, code" /></label>
        <label className="check"><input type="checkbox" checked={onlyReviewed} onChange={e => setOnlyReviewed(e.target.checked)} /><span>Clinician-reviewed only</span></label>
      </div>
      <ErrorText error={load.error} />
      <ErrorText error={get.error} onDismiss={get.clearError} />
      {items && !shown.length && <p className="muted">{items.length ? 'Nothing matches.' : 'Nothing is published yet.'}</p>}

      <div className="market">
        {shown.map(s => {
          const copy = library.find(r => r.origin?.downloaded_from === s.scenario_id)
          return (
            <article key={s.code} className="panel market-card">
              <div className="head-row"><h3>{s.title}</h3><ReviewBadge state={s.review_state} /></div>
              <p>{s.description}</p>
              <p className="muted small">{s.environment} · {s.crowdedness} · {s.difficulty} · v{s.version}</p>
              <div className="actions wrap">
                <span className="launch-code small-code" aria-label="Launch code">{s.code}</span>
                {copy
                  ? <button type="button" onClick={() => onDownloaded(copy.scenario_id)}>Open your copy</button>
                  : <button type="button" className="primary" disabled={get.pending}
                      onClick={async () => { const d = await get.run(() => api.download(s.code)); if (d) onDownloaded(d.scenario_id) }}>Download a copy</button>}
              </div>
            </article>
          )
        })}
      </div>
    </div>
  )
}
