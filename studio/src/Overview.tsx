import { useEffect, useState } from 'react'
import { api, isDownloaded, type ActiveSession, type LibraryRow, type ScenarioConfig } from './api'
import type { Page } from './App'
import { ErrorText, fmtDate, ReviewBadge, useAction } from './ui'

interface Props {
  visible: boolean; version: number
  go: (page: Page) => void
  onOpen: (id: string, downloaded: boolean) => void
  onEdit: (id: string, config: ScenarioConfig) => void
  onDebrief: (sessionId: string) => void
}

/** Where things stand: the last session, the scenario worked on last, and what is in the library. */
export default function Overview({ visible, version, go, onOpen, onEdit, onDebrief }: Props) {
  const [rows, setRows] = useState<LibraryRow[]>([])
  const [sessions, setSessions] = useState<ActiveSession[]>([])
  const load = useAction()
  const edit = useAction()
  useEffect(() => {
    if (!visible) return
    void load.run(async () => {
      const [r, s] = await Promise.all([api.library(), api.active()])
      setRows(r); setSessions(s)
    })
  }, [visible, version, load.run])

  const last = rows[0]              // the server lists newest first
  const session = sessions[0]
  const lastOfSession = session && rows.find(r => r.code === session.code)
  const mine = rows.filter(r => !isDownloaded(r.origin))
  const published = rows.filter(r => r.published_version != null)

  return (
    <div>
      <div className="head-row"><h2>Overview</h2></div>
      <ErrorText error={load.error} />

      <div className="grid2">
        <section className="panel lead">
          <h3>Last session</h3>
          {session ? <>
            <p><strong>{session.title}</strong> <code>{session.code}</code></p>
            <p className="muted">Started {fmtDate(session.started_at)} · {session.submitted ? 'diagnosis submitted' : 'in progress'} · headset {session.runtime_connected ? 'connected' : 'not connected'}</p>
            <div className="actions wrap">
              {!session.submitted && <button type="button" className="primary" onClick={() => go('director')}>Open live director</button>}
              <button type="button" onClick={() => onDebrief(session.session_id)}>Open debrief</button>
              {lastOfSession && <button type="button" onClick={() => onOpen(lastOfSession.scenario_id, isDownloaded(lastOfSession.origin))}>Open scenario</button>}
            </div>
          </> : <p className="muted">No scenario session has run since the server started. Publish a scenario and start it in the MedSim XR app with its launch code.</p>}
        </section>

        <section className="panel lead">
          <h3>Last scenario</h3>
          {last ? <>
            <p><strong>{last.title}</strong> <ReviewBadge state={last.review_state} /></p>
            <p className="muted">v{last.version}, {fmtDate(last.created_at)} · {last.environment} · {last.difficulty}
              {last.published_version != null ? <> · published as <code>{last.code}</code></> : ' · not published'}</p>
            <div className="actions wrap">
              <button type="button" className="primary" disabled={edit.pending}
                onClick={() => edit.run(async () => onEdit(last.scenario_id, (await api.scenario(last.scenario_id)).config))}>Continue in the generator</button>
              <button type="button" onClick={() => onOpen(last.scenario_id, isDownloaded(last.origin))}>Open</button>
            </div>
            <ErrorText error={edit.error} />
          </> : <p className="muted">No scenarios yet.</p>}
        </section>
      </div>

      <div className="stats">
        <button type="button" className="stat" onClick={() => go('mine')}><span className="stat-value">{mine.length}</span>My scenarios</button>
        <button type="button" className="stat" onClick={() => go('downloaded')}><span className="stat-value">{rows.length - mine.length}</span>Downloaded</button>
        <button type="button" className="stat" onClick={() => go('marketplace')}><span className="stat-value">{published.length}</span>Published</button>
        <button type="button" className="stat" onClick={() => go('director')}><span className="stat-value">{sessions.filter(s => !s.submitted).length}</span>Sessions in progress</button>
      </div>

      <div className="actions wrap">
        <button type="button" className="primary" onClick={() => go('generator')}>Create a scenario</button>
        <button type="button" onClick={() => go('marketplace')}>Browse the marketplace</button>
      </div>
    </div>
  )
}
