import { useCallback, useEffect, useState } from 'react'
import { api, isDownloaded, type LibraryRow, type ScenarioConfig, type ScenarioDefinition, type VersionRow } from './api'
import DefinitionView from './Definition'
import { ErrorText, fmtDate, KindBadge, ReviewBadge, StageStrip, useAction } from './ui'

const human = (s: string) => s.replace(/_/g, ' ')

interface Props {
  /** 'mine': created or duplicated here. 'downloaded': from the marketplace or an imported file. */
  scope: 'mine' | 'downloaded'
  version: number; visible: boolean; focus?: string | null
  onEdit: (id: string, config: ScenarioConfig) => void
  onChanged: () => void
  /** Show a scenario wherever it belongs (a duplicate of a download lands in My scenarios). */
  onOpen: (id: string, downloaded: boolean) => void
}

export default function Library({ scope, version, visible, focus, onEdit, onChanged, onOpen }: Props) {
  const [rows, setRows] = useState<LibraryRow[] | null>(null)
  const [selected, setSelected] = useState<string | null>(null)
  const list = useAction()
  const imp = useAction()
  const [note, setNote] = useState<string | null>(null)
  const [kind, setKind] = useState<'all' | 'single' | 'journey'>('all')
  const shown = (rows ?? []).filter(r => kind === 'all' || (r.kind ?? 'single') === kind)

  const reload = useCallback(() => list.run(async () =>
    setRows((await api.library()).filter(r => isDownloaded(r.origin) === (scope === 'downloaded')))), [list.run, scope])
  useEffect(() => { if (visible) void reload() }, [visible, version, reload])
  useEffect(() => { if (focus) setSelected(focus) }, [focus])

  async function importFile(file: File) {
    setNote(null)
    const d = await imp.run(async () => api.import(JSON.parse(await file.text())))
    if (d) {
      setNote(`Imported "${d.title}" as a new draft. Imports always start as draft; any review state in the file is recorded as a claim only.`)
      await reload(); onChanged()
      setSelected(d.scenario_id)
    }
  }

  return (
    <div className="library">
      <div className="head-row">
        <h2>{scope === 'mine' ? 'My scenarios' : 'Downloaded scenarios'}</h2>
        <div className="actions">
          <button type="button" onClick={() => void reload()} disabled={list.pending}>{list.pending ? 'Loading…' : 'Refresh'}</button>
          {scope === 'downloaded' && <label className="button">
            {imp.pending ? 'Importing…' : 'Import a scenario file'}
            <input type="file" accept="application/json,.json" hidden disabled={imp.pending}
              onChange={e => { const f = e.target.files?.[0]; e.target.value = ''; if (f) void importFile(f) }} />
          </label>}
        </div>
      </div>
      <p className="muted">{scope === 'mine'
        ? 'Scenarios created in the generator or duplicated here.'
        : 'Copies taken from the marketplace or imported from a file. They start as drafts: review and publish them yourself before use.'}</p>
      <ErrorText error={list.error} />
      <ErrorText error={imp.error} onDismiss={imp.clearError} />
      {note && <div className="notice" role="status">{note}</div>}

      {rows && (
        <div className="seg" role="group" aria-label="Filter by type">
          {(['all', 'journey', 'single'] as const).map(k => (
            <button key={k} type="button" aria-pressed={kind === k} onClick={() => setKind(k)}>
              {{ all: 'All', journey: 'Multi-stage journeys', single: 'Single encounters' }[k]} ({k === 'all' ? rows.length : rows.filter(r => (r.kind ?? 'single') === k).length})
            </button>
          ))}
        </div>
      )}
      {rows && (
        <div className="table-wrap">
          <table className="table selectable">
            <thead>
              <tr><th>Title</th><th>Type</th><th>Code</th><th>Version</th><th>Review</th><th>Published</th><th>Environment</th><th>Difficulty</th><th>AI</th></tr>
            </thead>
            <tbody>
              {shown.map(r => (
                <tr key={r.scenario_id} className={selected === r.scenario_id ? 'selected' : ''}>
                  <td>
                    <button type="button" className="rowlink" aria-pressed={selected === r.scenario_id}
                      onClick={() => setSelected(r.scenario_id)}>{r.title}</button>
                    <StageStrip stages={r.stages ?? []} />
                  </td>
                  <td><KindBadge kind={r.kind} stages={r.stages?.length} /></td>
                  <td><code>{r.code}</code></td>
                  <td>v{r.version}{r.versions > 1 && <span className="muted"> ({r.versions} versions)</span>}</td>
                  <td><ReviewBadge state={r.review_state} /></td>
                  <td>{r.published_version != null ? `Yes (v${r.published_version})` : 'No'}</td>
                  <td>{human(r.environment)}</td>
                  <td>{human(r.difficulty)}</td>
                  <td>{r.ai_generated ? <span className="tag">AI text</span> : ''}</td>
                </tr>
              ))}
              {!shown.length && <tr><td colSpan={9} className="muted">{rows.length ? 'Nothing of this type.' : scope === 'mine' ? 'Nothing here yet. Create one in the generator.' : 'Nothing downloaded yet. Browse the marketplace or import a file.'}</td></tr>}
            </tbody>
          </table>
        </div>
      )}

      {selected && rows?.some(r => r.scenario_id === selected) &&
        <Detail key={selected} id={selected} onChanged={async () => { await reload(); onChanged() }} onSelect={id => scope === 'mine' ? setSelected(id) : onOpen(id, false)} onEdit={onEdit} />}
    </div>
  )
}

function Detail({ id, onChanged, onSelect, onEdit }: {
  id: string
  onChanged: () => Promise<unknown>
  onSelect: (id: string) => void
  onEdit: (id: string, config: ScenarioConfig) => void
}) {
  const [def, setDef] = useState<ScenarioDefinition | null>(null)
  const [versions, setVersions] = useState<VersionRow[]>([])
  const act = useAction()
  const load = useAction()
  const [msg, setMsg] = useState<string | null>(null)

  const refresh = useCallback(() => load.run(async () => {
    const [d, v] = await Promise.all([api.scenario(id), api.versions(id)])
    setDef(d); setVersions(v)
  }), [id, load.run])
  useEffect(() => { void refresh() }, [refresh])

  /** Run a mutation, then reload both this panel and the table. */
  async function doAct(fn: () => Promise<ScenarioDefinition>, message?: string, then?: (d: ScenarioDefinition) => void) {
    setMsg(null)
    const d = await act.run(fn)
    if (!d) return
    if (message) setMsg(message)
    await Promise.all([refresh(), onChanged()])
    then?.(d)
  }

  function exportJson() {
    if (!def) return
    const url = URL.createObjectURL(new Blob([JSON.stringify(def, null, 2)], { type: 'application/json' }))
    const a = document.createElement('a')
    a.href = url; a.download = `${def.code}-v${def.version}.json`; a.click()
    URL.revokeObjectURL(url)
  }

  async function copyCode() {
    if (!def) return
    try { await navigator.clipboard.writeText(def.code); setMsg(`Copied ${def.code}.`) }
    catch { setMsg(`Could not copy automatically. The code is ${def.code}.`) }
  }

  if (!def) return <section className="panel"><ErrorText error={load.error} />{load.pending && <p className="muted">Loading…</p>}</section>

  const state = def.review.state
  const busy = act.pending
  return (
    <section className="panel">
      <div className="head-row">
        <h3>{def.title}</h3>
        <ReviewBadge state={state} />
      </div>
      <ErrorText error={load.error} />

      {def.published ? (
        <div className="launch">
          <div className="launch-code" aria-label="Launch code">{def.code}</div>
          <p>Enter this code in the MedSim XR app on the Vision Pro, or pick the scenario from its list.</p>
          <button type="button" onClick={copyCode}>Copy launch code</button>
        </div>
      ) : (
        <p className="muted">Not published. Launch code <code>{def.code}</code> works only after publishing.</p>
      )}

      <dl className="kv">
        <dt>Version</dt><dd>v{def.version} of {versions.length}, created {fmtDate(def.created_at)}</dd>
        <dt>Review</dt>
        <dd>
          {state === 'draft' && 'Draft. Not shown to students until published.'}
          {state === 'experimental' && 'Experimental. Not clinician-reviewed.'}
          {state === 'clinician_reviewed' && <>Reviewed by {def.review.reviewer_name ?? 'unknown'}{def.review.reviewer_role ? `, ${def.review.reviewer_role}` : ''}{def.review.reviewed_at ? `, ${fmtDate(def.review.reviewed_at)}` : ''}</>}
          {def.review.notes && <><br /><span className="muted">Notes: {def.review.notes}</span></>}
        </dd>
        {def.origin && <><dt>Origin</dt><dd>{originText(def.origin)}</dd></>}
        {def.narrative.ai_generated && <><dt>Narrative</dt><dd><span className="tag">AI text</span> The narrative was AI-generated.</dd></>}
        <dt>Versions</dt>
        <dd>{versions.map(v => (
          <span key={v.version} className="muted">v{v.version} {fmtDate(v.created_at)} {v.review_state}{v.published ? ', published' : ''}; </span>
        ))}</dd>
      </dl>

      <div className="actions wrap">
        <button type="button" disabled={busy} onClick={() => onEdit(def.scenario_id, def.config)}>Edit</button>
        <button type="button" disabled={busy} onClick={() => doAct(() => api.duplicate(id), 'Duplicated as a new draft.', d => onSelect(d.scenario_id))}>Duplicate</button>
        {def.published
          ? <button type="button" disabled={busy} onClick={() => doAct(() => api.unpublish(id), 'Unpublished.')}>Unpublish</button>
          : <button type="button" className="primary" disabled={busy} onClick={() => doAct(() => api.publish(id), state === 'draft' ? 'Published as experimental, not clinician-reviewed.' : 'Published.')}>Publish</button>}
        {state === 'draft' && <button type="button" disabled={busy} onClick={() => doAct(() => api.setState(id, 'experimental'))}>Mark experimental</button>}
        {state === 'experimental' && <button type="button" disabled={busy} onClick={() => doAct(() => api.setState(id, 'draft'), 'Back to draft. It is unpublished.')}>Back to draft</button>}
        <button type="button" onClick={exportJson}>Export JSON</button>
        {busy && <span className="muted">Working…</span>}
      </div>
      {!def.published && state === 'draft' && <p className="muted small">Publishing a draft makes it "experimental, not clinician-reviewed".</p>}
      <ErrorText error={act.error} onDismiss={act.clearError} />
      {msg && <div className="notice" role="status">{msg}</div>}

      <ReviewForm key={def.version + state} busy={busy} onSubmit={b => doAct(() => api.review(id, { ...b, attestation: true }), 'Clinician review recorded.')} />

      <h4>Definition</h4>
      <DefinitionView def={def} />
    </section>
  )
}

function originText(o: NonNullable<ScenarioDefinition['origin']>): string {
  const from = o.downloaded_from ? `Downloaded from the marketplace (${o.code ?? o.downloaded_from})` : o.duplicated_from ? `Duplicated from ${o.duplicated_from}` : o.imported_from ? `Imported from ${o.imported_from}` : 'Imported from a file'
  const claim = !o.claimed_review_state ? ''
    : o.downloaded_from ? `. The original is "${o.claimed_review_state.replace(/_/g, ' ')}"; this copy starts as a draft and needs its own review.`
    : `. The source claimed "${o.claimed_review_state}"; that claim was not accepted.`
  return `${from}${o.version != null ? ` v${o.version}` : ''}${claim}`
}

function ReviewForm({ busy, onSubmit }: { busy: boolean; onSubmit: (b: { reviewer_name: string; reviewer_role: string; notes: string }) => void }) {
  const [name, setName] = useState('')
  const [role, setRole] = useState('')
  const [notes, setNotes] = useState('')
  const [attest, setAttest] = useState(false)
  const ok = attest && name.trim() !== '' && role.trim() !== ''
  return (
    <details className="review-form">
      <summary>Record clinician review</summary>
      <form onSubmit={e => { e.preventDefault(); if (ok) onSubmit({ reviewer_name: name.trim(), reviewer_role: role.trim(), notes }) }}>
        <p className="muted small">This is the only way a scenario becomes "Clinician-reviewed". It applies to the latest version.</p>
        <div className="row">
          <label className="field"><span>Reviewer name</span><input value={name} onChange={e => setName(e.target.value)} required /></label>
          <label className="field"><span>Reviewer role</span><input value={role} onChange={e => setRole(e.target.value)} required /></label>
        </div>
        <label className="field"><span>Notes</span><textarea rows={2} value={notes} onChange={e => setNotes(e.target.value)} /></label>
        <label className="check">
          <input type="checkbox" checked={attest} onChange={e => setAttest(e.target.checked)} required />
          <span>I am a qualified clinician and I have reviewed this scenario</span>
        </label>
        <button type="submit" disabled={!ok || busy}>Record clinician review</button>
      </form>
    </details>
  )
}
