import { useEffect, useMemo, useRef, useState } from 'react'
import { api, ApiError, type Assist, type Issue, type ScenarioConfig, type ScenarioDefinition, type Template } from './api'
import type { EditRequest } from './App'
import DefinitionView from './Definition'
import { ErrorText, IssueList, useAction } from './ui'

const KIND_LABEL: Record<string, string> = {
  measurement_tool: 'Measurement tools',
  orthosis_size: 'Wrist support sizes',
  investigation: 'Investigations',
}

function blankConfig(t: Template): ScenarioConfig {
  return {
    template_id: t.template_id,
    title: '',
    environment: t.environments[0].id,
    difficulty: (t.difficulties.find(d => d.id === 'standard') ?? t.difficulties[0]).id,
    crowdedness: t.crowdedness[0].id,
    tools: [],
    bystander: 'none',
    teammate: 'none',
    learning_objectives: [],
    narrative: { description: '', patient_personality: '', bystander_lines: [], source: 'template' },
    seed: null,
  }
}

interface Props { edit: EditRequest; onSaved: () => void; onNew: () => void }

export default function Author(props: Props) {
  const [catalog, setCatalog] = useState<Template[] | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  useEffect(() => { api.catalog().then(setCatalog, e => setLoadError(e.message)) }, [])
  if (loadError) return <ErrorText error={`Could not load the catalogue: ${loadError}`} />
  if (!catalog) return <p className="muted">Loading catalogue…</p>
  if (!catalog.length) return <ErrorText error="The catalogue has no templates." />
  return <Form {...props} template={catalog[0]} />
}

function Form({ edit, template: t, onSaved, onNew }: Props & { template: Template }) {
  const [cfg, setCfg] = useState<ScenarioConfig>(() => edit.config ?? blankConfig(t))
  // The seed is only sent when typed: blank means random (create) or "keep the current seed" (edit).
  const [seedText, setSeedText] = useState('')
  const [linesText, setLinesText] = useState(() => (edit.config?.narrative.bystander_lines ?? []).join('\n'))
  const [focus, setFocus] = useState('')
  const [assist, setAssist] = useState<Assist | null>(null)
  const [preview, setPreview] = useState<ScenarioDefinition | null>(null)

  const seedValid = seedText.trim() === '' || /^-?\d+$/.test(seedText.trim())
  const config: ScenarioConfig = useMemo(() => ({
    ...cfg,
    narrative: { ...cfg.narrative, bystander_lines: linesText.split('\n').map(l => l.trim()).filter(Boolean) },
    seed: seedText.trim() === '' || !seedValid ? null : Number(seedText),
  }), [cfg, linesText, seedText, seedValid])

  // --- live validation, debounced ---
  const [issues, setIssues] = useState<Issue[]>([])
  const [validating, setValidating] = useState(true)
  const [validateError, setValidateError] = useState<string | null>(null)
  const latest = useRef(0)
  const key = JSON.stringify(config)
  useEffect(() => {
    const n = ++latest.current
    setValidating(true)
    const timer = setTimeout(() => {
      api.validate(config).then(v => {
        if (n !== latest.current) return
        setIssues(v.issues); setValidateError(null); setValidating(false)
      }, e => {
        if (n !== latest.current) return
        // A malformed body (e.g. title too short) comes back as 422 with pydantic issues.
        setIssues(e instanceof ApiError ? e.issues : []); setValidateError(e instanceof ApiError && e.issues.length ? null : e.message)
        setValidating(false)
      })
    }, 300)
    return () => clearTimeout(timer)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key])
  const errors = issues.filter(i => i.severity === 'error')
  const warnings = issues.filter(i => i.severity === 'warning')

  const draft = useAction()
  const prev = useAction()
  const save = useAction()

  const env = t.environments.find(e => e.id === cfg.environment)

  const set = (patch: Partial<ScenarioConfig>) => setCfg(c => ({ ...c, ...patch }))
  const setNarrative = (patch: Partial<ScenarioConfig['narrative']>) =>
    // Typing your own text turns a template-sourced narrative into instructor text; AI text keeps its AI label.
    setCfg(c => ({ ...c, narrative: { ...c.narrative, ...patch, source: c.narrative.source === 'template' ? 'instructor' : c.narrative.source } }))
  const toggle = (list: string[], id: string) => (list.includes(id) ? list.filter(x => x !== id) : [...list, id])

  function chooseEnvironment(id: string) {
    const next = t.environments.find(e => e.id === id)!
    // The one automatic correction we make: equipment the new setting cannot have is unchecked.
    set({ environment: id, tools: cfg.tools.filter(x => !next.unsupported_equipment.includes(x)) })
  }

  async function runAssist() {
    const r = await draft.run(() => api.assist({
      template_id: t.template_id, environment: cfg.environment, difficulty: cfg.difficulty,
      crowdedness: cfg.crowdedness, tools: cfg.tools, bystander: cfg.bystander, focus,
    }))
    if (!r) return
    setAssist(r)
    setLinesText(r.bystander_lines.join('\n'))
    setCfg(c => ({
      ...c,
      learning_objectives: r.learning_objectives,
      narrative: {
        ...c.narrative, description: r.description, patient_personality: r.patient_personality,
        source: r.source === 'llm' ? 'llm' : c.narrative.source,
      },
    }))
  }

  async function runPreview() {
    const d = await prev.run(() => api.preview(config))
    if (d) setPreview(d)
  }

  async function runSave() {
    const d = await save.run(() => (edit.scenarioId ? api.update(edit.scenarioId, config) : api.create(config)))
    if (d) onSaved()
  }

  const canSave = errors.length === 0 && !validating && !validateError && seedValid && !save.pending

  return (
    <div className="author">
      <div className="head-row">
        <h2>{edit.scenarioId ? 'Edit scenario' : 'New scenario'}</h2>
        {edit.scenarioId && <button type="button" onClick={onNew}>Start a new scenario instead</button>}
      </div>
      <p className="muted">Template: {t.label}. {t.summary} {t.clinical_review}</p>
      {edit.scenarioId && <p className="notice">Saving creates a new draft version of this scenario. A published version stays live until you publish again.</p>}

      <div className="split">
        <form className="form" onSubmit={e => e.preventDefault()}>
          <label className="field">
            <span>Title</span>
            <input value={cfg.title} maxLength={80} onChange={e => set({ title: e.target.value })} />
          </label>

          <fieldset>
            <legend>Environment</legend>
            <div className="cards">
              {t.environments.map(e => (
                <label key={e.id} className={`card${cfg.environment === e.id ? ' selected' : ''}`}>
                  <input type="radio" name="environment" checked={cfg.environment === e.id} onChange={() => chooseEnvironment(e.id)} />
                  <strong>{e.label}</strong>
                  <span className="muted">{e.brief}</span>
                </label>
              ))}
              {t.unsupported_environments.map(e => (
                <label key={e.id} className="card disabled">
                  <input type="radio" name="environment" disabled />
                  <strong>{e.label}</strong>
                  <span className="muted">Not supported: {e.reason}</span>
                </label>
              ))}
            </div>
          </fieldset>

          <div className="row">
            <label className="field">
              <span>Difficulty</span>
              <select value={cfg.difficulty} onChange={e => set({ difficulty: e.target.value })}>
                {t.difficulties.map(d => <option key={d.id} value={d.id}>{d.label}</option>)}
              </select>
              <small className="muted">{t.difficulties.find(d => d.id === cfg.difficulty)?.description}</small>
            </label>
            <label className="field">
              <span>Crowdedness</span>
              <select value={cfg.crowdedness} onChange={e => set({ crowdedness: e.target.value })}>
                {t.crowdedness.map(c => <option key={c.id} value={c.id}>{c.label}</option>)}
              </select>
              <small className="muted">{(() => { const c = t.crowdedness.find(x => x.id === cfg.crowdedness); return c ? `Noise ${Math.round(c.noise * 100)}%, ${c.figures} figure${c.figures === 1 ? '' : 's'} in the room` : '' })()}</small>
            </label>
          </div>

          <fieldset>
            <legend>Equipment</legend>
            {Object.keys(KIND_LABEL).concat(t.equipment.map(x => x.kind).filter(k => !(k in KIND_LABEL))).filter((k, i, a) => a.indexOf(k) === i).map(kind => {
              const items = t.equipment.filter(x => x.kind === kind)
              if (!items.length) return null
              return (
                <div key={kind} className="group">
                  <div className="group-title">{KIND_LABEL[kind] ?? kind}</div>
                  {items.map(x => {
                    const blocked = !!env?.unsupported_equipment.includes(x.id)
                    const checked = cfg.tools.includes(x.id)
                    return (
                      <label key={x.id} className={`check${blocked ? ' disabled' : ''}`}>
                        <input type="checkbox" checked={checked} disabled={blocked && !checked}
                          onChange={() => set({ tools: toggle(cfg.tools, x.id) })} />
                        <span>{x.label}</span>
                        {blocked && <span className="muted"> not available in {env?.label}</span>}
                      </label>
                    )
                  })}
                </div>
              )
            })}
          </fieldset>

          <div className="row">
            <label className="field">
              <span>Bystander behaviour</span>
              <select value={cfg.bystander} onChange={e => set({ bystander: e.target.value })}>
                {t.bystander_behaviors.map(b => <option key={b.id} value={b.id}>{b.label}</option>)}
              </select>
            </label>
            <label className="field">
              <span>Teammate behaviour</span>
              <select value={cfg.teammate} onChange={e => set({ teammate: e.target.value })}>
                {t.teammate_behaviors.map(b => <option key={b.id} value={b.id}>{b.label}</option>)}
              </select>
            </label>
          </div>

          <fieldset>
            <legend>Learning objectives (at least one)</legend>
            {t.learning_objectives.map(o => (
              <label key={o.id} className="check">
                <input type="checkbox" checked={cfg.learning_objectives.includes(o.id)}
                  onChange={() => set({ learning_objectives: toggle(cfg.learning_objectives, o.id) })} />
                <span>{o.label}{o.needs_kind && <span className="muted"> (needs {o.needs_kind.replace('_', ' ')})</span>}</span>
              </label>
            ))}
          </fieldset>

          <fieldset>
            <legend>Narrative (optional)</legend>
            <p className="muted small">Must not name a finding, a result or the diagnosis. The server rejects text that does.</p>
            <label className="field">
              <span>Description</span>
              <textarea rows={3} value={cfg.narrative.description} onChange={e => setNarrative({ description: e.target.value })} />
            </label>
            <label className="field">
              <span>Patient personality</span>
              <textarea rows={2} value={cfg.narrative.patient_personality} onChange={e => setNarrative({ patient_personality: e.target.value })} />
            </label>
            <label className="field">
              <span>Bystander lines (one per line)</span>
              <textarea rows={3} value={linesText} onChange={e => { setLinesText(e.target.value); setNarrative({}) }} />
            </label>
            <p className="muted small">Narrative source: <code>{cfg.narrative.source}</code></p>

            <div className="assist">
              <label className="field">
                <span>What should this session train? (optional, for the draft)</span>
                <input value={focus} maxLength={300} onChange={e => setFocus(e.target.value)} />
              </label>
              <button type="button" onClick={runAssist} disabled={draft.pending}>{draft.pending ? 'Drafting…' : 'Draft with AI assistance'}</button>
            </div>
            <ErrorText error={draft.error} onDismiss={draft.clearError} />
            {assist && (
              <div className={`notice ${assist.source === 'llm' ? 'notice-ai' : ''}`} role="status">
                <p><strong>Source: {assist.source}</strong>{assist.model ? <> · model: {assist.model}</> : <> · model: none</>}</p>
                <p>
                  {assist.source === 'llm'
                    ? 'This text was written by an AI model. It needs human review before you save it.'
                    : 'No AI model was used. This text comes from the deterministic template.'}
                  {assist.requires_review && ' Review required.'}
                </p>
                {assist.notes.length > 0 && <ul>{assist.notes.map((n, i) => <li key={i}>{n}</li>)}</ul>}
              </div>
            )}
          </fieldset>

          <label className="field narrow">
            <span>Seed (blank = {edit.scenarioId ? 'keep current seed' : 'random'})</span>
            <input inputMode="numeric" value={seedText} onChange={e => setSeedText(e.target.value)} aria-invalid={!seedValid} />
            {!seedValid && <small className="issue-error">Seed must be a whole number.</small>}
          </label>
        </form>

        <aside className="side">
          <div className="sticky">
            <h3>Checks {validating && <span className="muted small">checking…</span>}</h3>
            <ErrorText error={validateError} />
            {!validating && !issues.length && !validateError && <p className="ok">No problems found.</p>}
            <IssueList issues={[...errors, ...warnings]} />
            <div className="actions">
              <button type="button" onClick={runPreview} disabled={prev.pending || errors.length > 0 || validating}>{prev.pending ? 'Building…' : 'Preview definition'}</button>
              <button type="button" className="primary" onClick={runSave} disabled={!canSave}>
                {save.pending ? 'Saving…' : edit.scenarioId ? 'Save as new version' : 'Save to library'}
              </button>
            </div>
            <ErrorText error={prev.error} />
            <ErrorText error={save.error} />
            <IssueList issues={[...prev.issues, ...save.issues]} />
          </div>
        </aside>
      </div>

      {preview && (
        <section className="panel">
          <div className="head-row"><h3>Definition preview</h3><button type="button" className="link" onClick={() => setPreview(null)}>Close</button></div>
          <p className="muted">Nothing is saved yet. This is what the server would generate.</p>
          <DefinitionView def={preview} />
        </section>
      )}
    </div>
  )
}
