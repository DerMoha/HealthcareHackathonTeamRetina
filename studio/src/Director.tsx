import { useCallback, useEffect, useRef, useState } from 'react'
import { api, directorSocketUrl, type ActiveSession, type DirectorState } from './api'
import { ErrorText, fmtTime, Meter, ReviewBadge } from './ui'

const BACKOFF_MS = [1000, 2000, 4000, 5000]

export default function Director({ active, onDebrief }: { active: boolean; onDebrief: (id: string) => void }) {
  const [sessions, setSessions] = useState<ActiveSession[] | null>(null)
  const [listError, setListError] = useState<string | null>(null)
  const [picked, setPicked] = useState<string | null>(null)

  useEffect(() => {
    if (!active) return
    let stop = false
    const tick = () => api.active().then(
      s => { if (!stop) { setSessions(s); setListError(null) } },
      e => { if (!stop) setListError(e.message) })
    void tick()
    const t = setInterval(tick, 3000)
    return () => { stop = true; clearInterval(t) }
  }, [active])

  // Newest session unless the instructor picked another one that is still running.
  const newest = sessions?.slice().sort((a, b) => b.started_at.localeCompare(a.started_at))[0]
  const current = sessions?.find(s => s.session_id === picked) ?? newest ?? null

  return (
    <div className="director">
      <div className="head-row">
        <h2>Live director</h2>
        <label className="inline">
          <span>Session</span>
          <select value={current?.session_id ?? ''} onChange={e => setPicked(e.target.value)} disabled={!sessions?.length}>
            {!sessions?.length && <option value="">No running scenario sessions</option>}
            {sessions?.map(s => (
              <option key={s.session_id} value={s.session_id}>
                {s.title} ({s.code}) · started {fmtTime(s.started_at)}{s.submitted ? ' · submitted' : ''}
              </option>
            ))}
          </select>
        </label>
      </div>
      <ErrorText error={listError} />
      {sessions && !sessions.length && (
        <p className="muted">Nothing is running. Start a scenario session from the MedSim XR app; it appears here within a few seconds. The list refreshes every 3 s.</p>
      )}
      {current && <Live key={current.session_id} id={current.session_id} onDebrief={() => onDebrief(current.session_id)} />}
    </div>
  )
}

interface Pending { event_id: string; kind: string; params: Record<string, unknown> }
interface Rejection { id: number; event_id: string; reason: string }

function Live({ id, onDebrief }: { id: string; onDebrief: () => void }) {
  const [ds, setDs] = useState<DirectorState | null>(null)
  const [open, setOpen] = useState(false)
  const [retryIn, setRetryIn] = useState<number | null>(null)
  const [closedReason, setClosedReason] = useState<string | null>(null)
  const [rejections, setRejections] = useState<Rejection[]>([])
  const [pendingCount, setPendingCount] = useState(0)
  const ws = useRef<WebSocket | null>(null)
  // Sent but not yet seen in an `interventions` entry. Re-sent with the same id after a reconnect; the server deduplicates.
  const pending = useRef(new Map<string, Pending>())
  const rejectSeq = useRef(0)

  useEffect(() => {
    let disposed = false
    let attempt = 0
    let timer: ReturnType<typeof setTimeout> | undefined

    function connect() {
      const sock = new WebSocket(directorSocketUrl(id))
      ws.current = sock
      sock.onopen = () => {
        attempt = 0; setOpen(true); setRetryIn(null); setClosedReason(null)
        pending.current.forEach(p => sock.send(JSON.stringify({ type: 'event', ...p })))
      }
      sock.onmessage = m => {
        let f: { type?: string } & Record<string, unknown>
        try { f = JSON.parse(m.data) } catch { return }
        if (f.type === 'state') {
          const s = f as unknown as DirectorState
          setDs(s)
          for (const i of s.interventions) pending.current.delete(i.event_id)
          setPendingCount(pending.current.size)
        } else if (f.type === 'rejected') {
          const eid = String(f.event_id ?? '')
          pending.current.delete(eid); setPendingCount(pending.current.size)
          setRejections(r => [...r, { id: ++rejectSeq.current, event_id: eid, reason: String(f.reason ?? 'rejected') }])
        }
      }
      sock.onclose = ev => {
        setOpen(false)
        if (disposed) return
        if (ev.code === 4404) { setClosedReason('The server does not know this session (closed with code 4404).'); return }
        const delay = BACKOFF_MS[Math.min(attempt++, BACKOFF_MS.length - 1)]
        setRetryIn(delay / 1000)
        timer = setTimeout(connect, delay)
      }
    }
    connect()
    return () => { disposed = true; clearTimeout(timer); ws.current?.close() }
  }, [id])

  const send = useCallback((kind: string, params: Record<string, unknown>) => {
    const ev: Pending = { event_id: crypto.randomUUID(), kind, params }
    pending.current.set(ev.event_id, ev); setPendingCount(pending.current.size)
    ws.current?.send(JSON.stringify({ type: 'event', ...ev }))
  }, [])

  const sc = ds?.scenario
  return (
    <div className="live">
      <div className="status-row">
        <span className={`chip ${open ? 'chip-ok' : 'chip-bad'}`}>Panel: {open ? 'connected' : retryIn ? `disconnected, retrying in ${retryIn} s` : closedReason ? 'closed' : 'connecting…'}</span>
        <span className={`chip ${ds?.runtime_connected ? 'chip-ok' : 'chip-warn'}`}>Headset: {ds ? (ds.runtime_connected ? 'connected' : 'not connected') : 'unknown'}</span>
        {pendingCount > 0 && <span className="chip">Sending {pendingCount} event{pendingCount === 1 ? '' : 's'}…</span>}
        <button type="button" onClick={onDebrief}>Open debrief</button>
      </div>
      <ErrorText error={closedReason} />
      {rejections.map(r => (
        <ErrorText key={r.id} error={`Event rejected: ${r.reason}`} onDismiss={() => setRejections(x => x.filter(y => y.id !== r.id))} />
      ))}
      {!ds && <p className="muted">Waiting for the first state from the server…</p>}

      {ds && sc && (
        <div className="grid2">
          <section className="panel">
            <div className="head-row"><h3>{sc.title}</h3><ReviewBadge state={sc.review_state} /></div>
            <dl className="kv">
              <dt>Code</dt><dd><code>{sc.code}</code></dd>
              <dt>Setting</dt><dd>{sc.environment_label}, {sc.difficulty}</dd>
              <dt>Noise level</dt><dd><Meter value={sc.noise_level} label="Noise level" /></dd>
              <dt>Bystander</dt><dd>{sc.bystander ? `${sc.bystander.name} (${sc.bystander.role_label}), ${sc.bystander.mood}` : 'none'}</dd>
              <dt>Helper present</dt><dd>{sc.teammate.present ? `Yes, ${sc.teammate.name}` : 'No'}</dd>
              <dt>Hint policy</dt><dd><code>{sc.hint_policy}</code></dd>
              <dt>Equipment</dt>
              <dd>
                <ul className="plain">{sc.equipment.map(e => (
                  <li key={e.id} className={e.available ? '' : 'muted'}>{e.label}: {e.available ? 'available' : 'not available'}</li>
                ))}</ul>
              </dd>
            </dl>
            <h4>Student activity</h4>
            <dl className="kv small">
              {Object.entries(ds.activity).map(([k, v]) => (
                <div key={k} className="kv-row"><dt>{k.replace(/_/g, ' ')}</dt><dd>{typeof v === 'boolean' ? (v ? 'yes' : 'no') : v}</dd></div>
              ))}
            </dl>
          </section>

          <section className="panel">
            <h3>Interventions</h3>
            <p className="muted small">Each action is sent to the headset.</p>
            <ul className="events">
              {ds.events.map(ev => <EventRow key={ev.kind} ev={ev} canSend={open} onSend={send} />)}
            </ul>
          </section>
        </div>
      )}

      {ds && (
        <section className="panel">
          <h3>Intervention log</h3>
          {ds.interventions.length === 0 ? <p className="muted">No interventions yet.</p> : (
            <table className="table compact">
              <thead><tr><th>Time</th><th>Action</th><th>Spoken line</th><th>Headset</th></tr></thead>
              <tbody>
                {ds.interventions.map(i => (
                  <tr key={i.event_id}>
                    <td>{fmtTime(i.at)}</td>
                    <td>{i.label}{Object.keys(i.params).length > 0 && <span className="muted"> {JSON.stringify(i.params)}</span>}</td>
                    <td>{i.line ? <>{i.line.speaker}: “{i.line.text}”</> : <span className="muted">none</span>}</td>
                    <td>{i.acknowledged ? (i.ack_detail ?? 'acknowledged') : <span className="waiting">waiting for the headset</span>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      )}
    </div>
  )
}

function EventRow({ ev, canSend, onSend }: { ev: DirectorState['events'][number]; canSend: boolean; onSend: (kind: string, params: Record<string, unknown>) => void }) {
  const [choice, setChoice] = useState('')
  const options = ev.options ?? []
  const value = choice || options[0]?.id || ''
  const needsParam = !!ev.param
  const ready = ev.enabled && canSend && (!needsParam || value !== '')
  return (
    <li className="event">
      <div className="event-main">
        {needsParam && (
          <select aria-label={`${ev.label}: ${ev.param}`} value={value} onChange={e => setChoice(e.target.value)} disabled={!ev.enabled || !options.length}>
            {options.map(o => <option key={o.id} value={o.id}>{o.label}</option>)}
          </select>
        )}
        <button type="button" disabled={!ready} onClick={() => onSend(ev.kind, needsParam ? { [ev.param!]: value } : {})}>{ev.label}</button>
      </div>
      {!ev.enabled && ev.reason && <div className="muted small">{ev.reason}</div>}
      {needsParam && ev.enabled && !options.length && <div className="muted small">No options to deliver.</div>}
    </li>
  )
}
