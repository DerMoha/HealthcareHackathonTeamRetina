import { useCallback, useEffect, useState } from 'react'
import { api, type ActiveSession, type Debrief, type Score } from './api'
import { ErrorText, fmtTime, ReviewBadge, useAction } from './ui'

const SCORE_TITLE: Record<string, string> = { core: 'Core: history, examination, reasoning', management: 'Investigation and management', fitting: 'Measurement and fitting' }

export default function DebriefTab({ sessionId, setSessionId, visible }: { sessionId: string; setSessionId: (id: string) => void; visible: boolean }) {
  const [sessions, setSessions] = useState<ActiveSession[]>([])
  const [typed, setTyped] = useState('')
  const [data, setData] = useState<Debrief | null>(null)
  const load = useAction()

  useEffect(() => {
    if (!visible) return
    let stop = false
    const tick = () => api.active().then(s => { if (!stop) setSessions(s) }, () => undefined)
    void tick()
    const t = setInterval(tick, 3000)
    return () => { stop = true; clearInterval(t) }
  }, [visible])

  const fetchDebrief = useCallback(async (id: string) => {
    if (!id) return
    const d = await load.run(() => api.debrief(id))
    if (d) setData(d)
  }, [load.run])

  // Opening the tab for a session (from the Director's button or a pick) loads it.
  useEffect(() => { if (visible && sessionId) { setData(null); void fetchDebrief(sessionId) } }, [visible, sessionId, fetchDebrief])

  return (
    <div className="debrief">
      <div className="head-row">
        <h2>Debrief</h2>
        <div className="actions wrap">
          <label className="inline">
            <span>Running session</span>
            <select value={sessions.some(s => s.session_id === sessionId) ? sessionId : ''} onChange={e => e.target.value && setSessionId(e.target.value)}>
              <option value="">Choose…</option>
              {sessions.map(s => <option key={s.session_id} value={s.session_id}>{s.title} ({s.code}) · {fmtTime(s.started_at)}{s.submitted ? ' · submitted' : ''}</option>)}
            </select>
          </label>
          <form className="inline" onSubmit={e => { e.preventDefault(); if (typed.trim()) setSessionId(typed.trim()) }}>
            <label className="inline"><span>or session id</span><input value={typed} onChange={e => setTyped(e.target.value)} /></label>
            <button type="submit" disabled={!typed.trim()}>Load</button>
          </form>
          <button type="button" onClick={() => void fetchDebrief(sessionId)} disabled={!sessionId || load.pending}>{load.pending ? 'Loading…' : 'Refresh'}</button>
        </div>
      </div>
      <ErrorText error={load.error} />
      {!sessionId && <p className="muted">Choose a session to see its debrief.</p>}
      {data && <Body d={data} />}
    </div>
  )
}

function ScoreRow({ id, s }: { id: string; s: Score }) {
  return (
    <div className="score">
      <div className="score-title">{SCORE_TITLE[id] ?? id}</div>
      <div className="score-value">{s.score} / {s.max_score}</div>
      {s.achievable_max != null && s.achievable_max !== s.max_score && <div className="muted">of {s.achievable_max} achievable here</div>}
      {s.achievable_max != null && s.achievable_max === s.max_score && <div className="muted">all points were achievable</div>}
      {s.not_assessable?.map(n => <div key={n.id} className="issue issue-warning small"><strong>{n.label}</strong> ({n.points} pts): {n.reason}</div>)}
    </div>
  )
}

function Body({ d }: { d: Debrief }) {
  const sc = d.scenario
  const fb = d.feedback
  const v = fb.diagnostic_assessment
  return (
    <>
      <section className="panel">
        <div className="head-row">
          <h3>Configuration used</h3>
          {sc && <ReviewBadge state={sc.review_state} />}
        </div>
        {sc ? (
          <p><strong>{sc.title}</strong> (<code>{sc.code}</code>, v{sc.version}, seed {sc.seed}). {sc.environment}, {sc.crowdedness.toLowerCase()}, {sc.difficulty.toLowerCase()}.
            Bystander: {sc.bystander.replace(/_/g, ' ')}. Teammate: {sc.teammate.replace(/_/g, ' ')}.</p>
        ) : <p>Fixed default case.</p>}
        {sc && sc.learning_objectives.length > 0 && <ul>{sc.learning_objectives.map(o => <li key={o.id}>{o.label}</li>)}</ul>}
      </section>

      <section className="panel lead">
        <h3>How to read these scores</h3>
        <ul>{d.interpretation.map((l, i) => <li key={i}>{l}</li>)}</ul>
      </section>

      <section className="panel">
        <h3>Scores</h3>
        <div className="scores">{Object.entries(d.scores).map(([id, s]) => <ScoreRow key={id} id={id} s={s} />)}</div>
      </section>

      {sc && (
        <section className="panel">
          <h3>Resources</h3>
          <table className="table compact">
            <thead><tr><th>Item</th><th>Available at start</th><th>Delivered</th><th>Used</th></tr></thead>
            <tbody>{d.resources.map(r => (
              <tr key={r.id}>
                <td>{r.label}</td><td>{r.available_at_start ? 'Yes' : 'No'}</td>
                <td>{r.delivered_at_seq != null ? `Yes, at step ${r.delivered_at_seq}` : 'No'}</td>
                <td>{r.used ? 'Yes' : 'No'}</td>
              </tr>
            ))}</tbody>
          </table>
        </section>
      )}

      <div className="grid2">
        <section className="panel">
          <h3>Interventions</h3>
          {d.interventions.length === 0 ? <p className="muted">None.</p> : (
            <ul className="plain">{d.interventions.map(i => (
              <li key={i.event_id}>{fmtTime(i.at)} {i.label}{i.line ? <> — {i.line.speaker}: “{i.line.text}”</> : ''}
                <span className="muted"> ({i.acknowledged ? (i.ack_detail ?? 'acknowledged') : 'never acknowledged by the headset'})</span></li>
            ))}</ul>
          )}
        </section>
        <section className="panel">
          <h3>Coaching hints given</h3>
          {d.hints.length === 0 ? <p className="muted">None.</p> : <ul className="plain">{d.hints.map(h => <li key={h.id}>{fmtTime(h.at)} {h.text}</li>)}</ul>}
        </section>
      </div>

      <section className="panel">
        <h3>Timeline of the student's decisions</h3>
        {d.timeline.length === 0 ? <p className="muted">Nothing recorded yet.</p> : (
          <table className="table compact">
            <thead><tr><th>#</th><th>Type</th><th>What happened</th></tr></thead>
            <tbody>{d.timeline.map((t, i) => (
              <tr key={i}><td>{t.seq}</td><td><span className={`tag tag-${t.type}`}>{t.type}</span></td><td>{t.label}</td></tr>
            ))}</tbody>
          </table>
        )}
      </section>

      <section className="panel">
        <h3>Feedback</h3>
        {d.diagnosis_submitted == null ? (
          <p className="notice">No diagnosis has been submitted yet. Feedback is withheld until the student submits one.</p>
        ) : (
          <>
            <p><strong>Submitted diagnosis:</strong> {d.diagnosis_submitted}</p>
            <p><strong>Verdict: {v.verdict.replace('_', ' ')}.</strong> {v.explanation}</p>
            <p>{fb.summary}</p>
            <div className="grid2">
              <div><h4>Strengths</h4>{fb.strengths.length ? <ul>{fb.strengths.map((s, i) => <li key={i}>{s}</li>)}</ul> : <p className="muted">None listed.</p>}</div>
              <div><h4>Missed</h4>{fb.missed.length ? <ul>{fb.missed.map((s, i) => <li key={i}>{s}</li>)}</ul> : <p className="muted">None listed.</p>}</div>
            </div>
          </>
        )}
      </section>
    </>
  )
}
