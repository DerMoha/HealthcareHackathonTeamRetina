import { useEffect, useMemo, useRef, useState } from 'react'
import { api, ApiError, type Advanced, type Assist, type HintPolicy, type Issue, type ScenarioConfig, type ScenarioDefinition, type Template } from './api'
import type { EditRequest } from './App'
import DefinitionView from './Definition'
import { ErrorText, IssueList, KindBadge, StageStrip, useAction } from './ui'

const KIND_LABEL: Record<string, string> = {
  measurement_tool: 'Measurement tools',
  orthosis_size: 'Wrist support sizes',
  investigation: 'Investigations',
}
const HINT_LABEL: Record<HintPolicy, string> = {
  auto: 'Hints appear on their own', on_request: 'Hints only when the student asks', off: 'No hints',
}
const pct = (n: number) => `${Math.round(n * 100)}%`

function blankConfig(t: Template, title = ''): ScenarioConfig {
  return {
    template_id: t.template_id,
    title,
    environment: t.environments[0].id,
    difficulty: (t.difficulties.find(d => d.id === 'standard') ?? t.difficulties[0]).id,
    crowdedness: t.crowdedness[0].id,
    tools: t.equipment.filter(e => !t.environments[0].unsupported_equipment.includes(e.id)).map(e => e.id),
    bystander: 'none',
    teammate: 'none',
    learning_objectives: [],
    narrative: { description: '', patient_personality: '', bystander_lines: [], source: 'template' },
    advanced: {},
    seed: null,
  }
}

/** Non-default advanced overrides, so basic mode can say they are still applied. */
function overrides(a: Advanced | undefined): number {
  if (!a) return 0
  return [a.hint_policy, a.interject_every_s, a.crowd_figures].filter(v => v != null).length
    + Object.keys(a.stage_noise ?? {}).length
}

interface Props { edit: EditRequest; onSaved: (scenarioId: string) => void; onNew: () => void }

export default function Author(props: Props) {
  const [catalog, setCatalog] = useState<Template[] | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  useEffect(() => { api.catalog().then(setCatalog, e => setLoadError(e.message)) }, [])
  if (loadError) return <ErrorText error={`Could not load the catalogue: ${loadError}`} />
  if (!catalog) return <p className="muted">Loading catalogue…</p>
  if (!catalog.length) return <ErrorText error="The catalogue has no templates." />
  return <Form {...props} catalog={catalog} />
}

// Generator steps, and which validation fields belong to each (for the error count on the step).
interface Step { id: string; label: string; fields: string[]; advancedOnly?: boolean }
const STEPS: Step[] = [
  { id: 'case', label: 'Case', fields: ['template_id'] },
  { id: 'setting', label: 'Setting', fields: ['title', 'environment', 'difficulty', 'crowdedness'] },
  { id: 'people', label: 'People', fields: ['bystander', 'teammate'] },
  { id: 'equipment', label: 'Equipment', fields: ['tools'] },
  { id: 'goals', label: 'Learning goals', fields: ['learning_objectives'] },
  { id: 'story', label: 'Story', fields: ['narrative'] },
  { id: 'advanced', label: 'Advanced', fields: ['advanced', 'seed'], advancedOnly: true },
  { id: 'review', label: 'Review and save', fields: [] },
]

function Form({ edit, catalog, onSaved, onNew }: Props & { catalog: Template[] }) {
  const [cfg, setCfg] = useState<ScenarioConfig>(() => {
    if (edit.config) return { ...edit.config, advanced: edit.config.advanced ?? {} }
    return blankConfig(catalog.find(t => t.template_id === 'wrist_trauma_001') ?? catalog[0])
  })
  const t = catalog.find(x => x.template_id === cfg.template_id) ?? catalog[0]
  const journey = t.kind === 'journey'
  const [mode, setMode] = useState<'basic' | 'advanced'>(() =>
    (localStorage.getItem('studio.mode') as 'basic' | 'advanced' | null) ?? (overrides(edit.config?.advanced) ? 'advanced' : 'basic'))
  useEffect(() => { localStorage.setItem('studio.mode', mode) }, [mode])
  const steps = STEPS.filter(s => mode === 'advanced' || !s.advancedOnly)

  // The seed is only sent when typed: blank means random (create) or "keep the current seed" (edit).
  const [seedText, setSeedText] = useState('')
  const [linesText, setLinesText] = useState(() => (edit.config?.narrative.bystander_lines ?? []).join('\n'))
  const [focus, setFocus] = useState('')
  const [assist, setAssist] = useState<Assist | null>(null)
  const [preview, setPreview] = useState<ScenarioDefinition | null>(null)

  const seedValid = seedText.trim() === '' || /^\d+$/.test(seedText.trim())
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
  const save = useAction()

  const env = t.environments.find(e => e.id === cfg.environment)
  const adv = cfg.advanced ?? {}

  const set = (patch: Partial<ScenarioConfig>) => setCfg(c => ({ ...c, ...patch }))
  const setAdv = (patch: Partial<Advanced>) => setCfg(c => ({ ...c, advanced: { ...c.advanced, ...patch } }))
  const setNarrative = (patch: Partial<ScenarioConfig['narrative']>) =>
    // Typing your own text turns a template-sourced narrative into instructor text; AI text keeps its AI label.
    setCfg(c => ({ ...c, narrative: { ...c.narrative, ...patch, source: c.narrative.source === 'template' ? 'instructor' : c.narrative.source } }))
  const toggle = (list: string[], id: string) => (list.includes(id) ? list.filter(x => x !== id) : [...list, id])

  function chooseCase(next: Template) {
    if (next.template_id === cfg.template_id) return
    // Every option id belongs to one case: switching starts from that case's defaults, keeping the title.
    setCfg(blankConfig(next, cfg.title)); setLinesText(''); setAssist(null); setPreview(null)
  }

  function chooseEnvironment(id: string) {
    const next = t.environments.find(e => e.id === id)!
    // The one automatic correction we make: equipment the new setting cannot have is unchecked.
    set({ environment: id, tools: cfg.tools.filter(x => !next.unsupported_equipment.includes(x)) })
  }

  function setStageNoise(id: string, value: number | null) {
    const next = { ...(adv.stage_noise ?? {}) }
    if (value == null) delete next[id]; else next[id] = value
    setAdv({ stage_noise: next })
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

  async function runSave() {
    const d = await save.run(() => (edit.scenarioId ? api.update(edit.scenarioId, config) : api.create(config)))
    if (d) onSaved(d.scenario_id)
  }

  const [stepId, setStepId] = useState(edit.scenarioId ? 'setting' : 'case')
  const at = Math.max(0, steps.findIndex(s => s.id === stepId))
  const step = steps[at]
  const stepErrors = (s: Step) => errors.filter(i => s.fields.some(f => i.field === f || i.field.startsWith(f + '.'))).length
  // The definition this configuration produces, rebuilt whenever it is valid: every step shows its consequences.
  useEffect(() => {
    if (validating || errors.length || validateError) return
    let stale = false
    api.preview(config).then(d => { if (!stale) setPreview(d) }, () => {})
    return () => { stale = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, validating, errors.length, validateError])

  const canSave = errors.length === 0 && !validating && !validateError && seedValid && !save.pending
  const nOverrides = overrides(adv)
  const crowd = t.crowdedness.find(x => x.id === cfg.crowdedness)
  const level = t.difficulties.find(d => d.id === cfg.difficulty)
  // Same rule as the server (studio.generate), so defaults show before the form is valid.
  const placeNoise = (s: { id: string; noise: number }) =>
    Math.round(Math.min(1, s.noise + (env?.ambient_level ?? 0) + (crowd?.noise ?? 0)) * 100) / 100

  return (
    <div className="author">
      <div className="head-row">
        <h2>Scenario generator{edit.scenarioId ? ': editing' : ''}</h2>
        <div className="actions">
          <div className="mode-toggle" role="group" aria-label="Generator mode">
            <button type="button" aria-pressed={mode === 'basic'} onClick={() => setMode('basic')}>Basic</button>
            <button type="button" aria-pressed={mode === 'advanced'} onClick={() => setMode('advanced')}>Advanced</button>
          </div>
          {edit.scenarioId && <button type="button" onClick={onNew}>Start a new scenario instead</button>}
        </div>
      </div>
      <p className="muted">
        A scenario sets up <strong>how</strong> a reviewed case is played: where, how hard, who else is there and what equipment is at hand.
        {mode === 'basic' ? ' Advanced mode adds fine control over coaching, crowd, timing, per-place noise and the patient\'s manner.' : ' Advanced mode is on: extra controls are marked "Advanced".'}
      </p>
      {edit.scenarioId && <p className="notice">Saving creates a new draft version of this scenario. A published version stays live until you publish again.</p>}
      {mode === 'basic' && nOverrides > 0 && (
        <p className="notice">{nOverrides} advanced setting{nOverrides === 1 ? ' is' : 's are'} still applied.{' '}
          <button type="button" className="link" onClick={() => setMode('advanced')}>Show</button>
          <button type="button" className="link" onClick={() => set({ advanced: {} })}>Reset to defaults</button></p>
      )}

      <div className="split">
        <form className="form" onSubmit={e => e.preventDefault()}>
          <ol className="steps" aria-label="Generator steps">
            {steps.map((s, n) => (
              <li key={s.id}>
                <button type="button" className={n === at ? 'step active' : 'step'} aria-current={n === at ? 'step' : undefined} onClick={() => setStepId(s.id)}>
                  <span className="step-n">{n + 1}</span>{s.label}
                  {stepErrors(s) > 0 && <span className="chip chip-bad">{stepErrors(s)}</span>}
                </button>
              </li>
            ))}
          </ol>

          {step.id === 'case' && <>
            <p className="effect">The case decides the patient, the history, the findings and how the student is scored. Everything else in this generator is built around it.</p>
            {edit.scenarioId && <p className="muted small">The case of a saved scenario cannot change. Start a new scenario to use another case.</p>}
            <p className="muted small">Multi-stage journeys move the student through several places with a team; single encounters happen in one room.</p>
            <div className="cards">
              {[...catalog].sort((a, b) => Number(b.kind === 'journey') - Number(a.kind === 'journey')).map(c => {
                const locked = !!edit.scenarioId && c.template_id !== cfg.template_id
                return (
                  <label key={c.template_id} className={`card${c.template_id === cfg.template_id ? ' selected' : ''}${locked ? ' disabled' : ''}`}>
                    <input type="radio" name="case" checked={c.template_id === cfg.template_id} disabled={locked} onChange={() => chooseCase(c)} />
                    <KindBadge kind={c.kind} stages={c.stages.length} />
                    <strong>{c.label}</strong>
                    <span className="muted">{c.summary}</span>
                    <StageStrip stages={c.stages.map(s => s.label)} />
                    <span className="muted small">{c.clinical_review}</span>
                  </label>
                )
              })}
            </div>
          </>}

          {step.id === 'setting' && <>
            <label className="field">
              <span>Title</span>
              <input value={cfg.title} maxLength={80} placeholder="e.g. Night roadside, busy crowd" onChange={e => set({ title: e.target.value })} />
              <small className="muted">Shown to students and in the scenario list. Must not hint at the diagnosis.</small>
            </label>

            {journey && (
              <div>
                <span className="group-title">The journey (fixed by the case)</span>
                <ol className="stages">
                  {t.stages.map(s => (
                    <li key={s.id}>
                      <strong>{s.label}</strong>
                      <div className="muted small">{s.team.join(', ')}</div>
                      <div className="muted small">{s.actions} team actions · noise {pct(adv.stage_noise?.[s.id] ?? placeNoise(s))}</div>
                    </li>
                  ))}
                </ol>
                <p className="muted small">The student moves through these places in this order with the team listed. The places, their order and the team are part of the reviewed case; the setting and crowd below add to each place's noise.</p>
              </div>
            )}

            <fieldset>
              <legend>{journey ? 'Conditions' : 'Environment'}</legend>
              <p className="effect">{journey ? 'Weather, time of day and location: how the patient talks about the surroundings, the noise, and which hospital investigations exist.' : 'The room the encounter takes place in: background noise, how the patient talks about it, and which equipment can exist there.'}</p>
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
                <small className="muted">{level?.description} Also sets how forthcoming the patient is.</small>
              </label>
              <label className="field">
                <span>{journey ? 'Onlookers' : 'Crowdedness'}</span>
                <select value={cfg.crowdedness} onChange={e => set({ crowdedness: e.target.value })}>
                  {t.crowdedness.map(c => <option key={c.id} value={c.id}>{c.label}</option>)}
                </select>
                <small className="muted">{crowd ? `Adds ${pct(crowd.noise)} noise and ${crowd.figures} background figure${crowd.figures === 1 ? '' : 's'}.` : ''}</small>
              </label>
            </div>
          </>}

          {step.id === 'people' && <>
            <p className="effect">{journey
              ? 'The ambulance and hospital teams come with the case. Here you add people around them.'
              : 'Who else is in the room besides the patient.'}</p>
            <div className="row">
              <label className="field">
                <span>Bystander</span>
                <select value={cfg.bystander} onChange={e => set({ bystander: e.target.value })}>
                  {t.bystander_behaviors.map(b => <option key={b.id} value={b.id}>{b.label}</option>)}
                </select>
                <small className="muted">Stands nearby and speaks up unprompted. The instructor can calm or agitate them live.</small>
              </label>
              <label className="field">
                <span>Helper</span>
                <select value={cfg.teammate} onChange={e => set({ teammate: e.target.value })}>
                  {t.teammate_behaviors.map(b => <option key={b.id} value={b.id}>{b.label}</option>)}
                </select>
                <small className="muted">Fetches equipment when asked. Can also be sent in later from the live director.</small>
              </label>
            </div>
          </>}

          {step.id === 'equipment' && (
            <fieldset>
              <legend>Equipment at the start</legend>
              <p className="effect">Only ticked items exist when the session starts. Anything unticked that the setting allows can be delivered live by the instructor. Missing equipment can make some score points unearnable (see Checks).</p>
              {journey && <p className="muted small">Investigations can only be requested once the patient reaches the emergency department.</p>}
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
          )}

          {step.id === 'goals' && (
            <fieldset>
              <legend>Learning goals (at least one)</legend>
              <p className="effect">What the debrief focuses on. Goals do not change the score; the case's rubric does.</p>
              {t.learning_objectives.map(o => (
                <label key={o.id} className="check">
                  <input type="checkbox" checked={cfg.learning_objectives.includes(o.id)}
                    onChange={() => set({ learning_objectives: toggle(cfg.learning_objectives, o.id) })} />
                  <span>{o.label}{o.needs_kind && <span className="muted"> (needs {o.needs_kind.replace('_', ' ')})</span>}</span>
                </label>
              ))}
            </fieldset>
          )}

          {step.id === 'story' && (
            <fieldset>
              <legend>Story (optional)</legend>
              <p className="effect">Framing text for the scenario card and the patient's manner. It must not name a finding, a result or the diagnosis; the server rejects text that does.</p>
              <label className="field">
                <span>Description</span>
                <textarea rows={3} value={cfg.narrative.description} onChange={e => setNarrative({ description: e.target.value })} placeholder={t.summary} />
              </label>
              {mode === 'advanced' ? <>
                <label className="field">
                  <span>Patient's manner <span className="tag">Advanced</span></span>
                  <textarea rows={2} value={cfg.narrative.patient_personality} onChange={e => setNarrative({ patient_personality: e.target.value })} placeholder="Blank: set by the difficulty" />
                </label>
                <label className="field">
                  <span>Bystander lines, one per line <span className="tag">Advanced</span></span>
                  <textarea rows={3} value={linesText} onChange={e => { setLinesText(e.target.value); setNarrative({}) }} placeholder="Blank: the case's own lines" />
                </label>
              </> : <p className="muted small">The patient's manner follows the difficulty. Switch to Advanced to write it yourself or to write the bystander's lines.</p>}
              <p className="muted small">Text source: <code>{cfg.narrative.source}</code></p>

              <div className="assist">
                <label className="field">
                  <span>What should this session train? (optional, for the draft)</span>
                  <input value={focus} maxLength={300} onChange={e => setFocus(e.target.value)} />
                </label>
                <button type="button" onClick={runAssist} disabled={draft.pending}>{draft.pending ? 'Drafting…' : 'Draft with AI assistance'}</button>
              </div>
              <ErrorText error={draft.error} onDismiss={draft.clearError} />
              {assist && (
                <div className={`notice ${assist.source !== 'template' ? 'notice-ai' : ''}`} role="status">
                  <p><strong>Source: {assist.source === 'demo' ? 'AI assistant (offline preview)' : assist.source}</strong>{assist.model ? <> · model: {assist.model}</> : <> · model: none</>}</p>
                  <p>
                    {assist.source === 'llm' ? 'This text was written by an AI model. It needs human review before you save it.'
                      : assist.source === 'demo' ? 'Preview of the drafting assistant for these choices. Read it before you save it.'
                      : 'No AI model was used. This text comes from the deterministic template.'}
                    {assist.requires_review && ' Review required.'}
                  </p>
                  {assist.notes.length > 0 && <ul>{assist.notes.map((n, i) => <li key={i}>{n}</li>)}</ul>}
                </div>
              )}
            </fieldset>
          )}

          {step.id === 'advanced' && <>
            <p className="effect">Each setting overrides what the basic choices imply. Leave one on "Default" to keep it.</p>
            <fieldset>
              <legend>Coaching</legend>
              <div className="override">
                <select value={adv.hint_policy ?? ''} onChange={e => setAdv({ hint_policy: (e.target.value || null) as HintPolicy | null })}>
                  <option value="">Default: {level ? HINT_LABEL[level.hint_policy] : ''} ({level?.label})</option>
                  {(Object.keys(HINT_LABEL) as HintPolicy[]).map(p => <option key={p} value={p}>{HINT_LABEL[p]}</option>)}
                </select>
              </div>
              <small className="muted">Decouples hints from the difficulty, e.g. a tense patient but full coaching.</small>
            </fieldset>

            <fieldset>
              <legend>Crowd and bystander</legend>
              <label className="field">
                <span>Background figures: {adv.crowd_figures ?? `default (${crowd?.figures ?? 0})`}</span>
                <div className="override">
                  <input type="range" min={0} max={8} value={adv.crowd_figures ?? crowd?.figures ?? 0} onChange={e => setAdv({ crowd_figures: Number(e.target.value) })} />
                  <button type="button" className="link" disabled={adv.crowd_figures == null} onClick={() => setAdv({ crowd_figures: null })}>Default</button>
                </div>
              </label>
              <label className="field">
                <span>Bystander speaks up every: {adv.interject_every_s ? `${adv.interject_every_s} s` : 'default (20–30 s, from the seed)'}</span>
                <div className="override">
                  <input type="range" min={10} max={120} step={5} value={adv.interject_every_s ?? 25} disabled={cfg.bystander === 'none'} onChange={e => setAdv({ interject_every_s: Number(e.target.value) })} />
                  <button type="button" className="link" disabled={adv.interject_every_s == null} onClick={() => setAdv({ interject_every_s: null })}>Default</button>
                </div>
                {cfg.bystander === 'none' && <small className="muted">Choose a bystander under People first.</small>}
              </label>
            </fieldset>

            {journey && (
              <fieldset>
                <legend>Noise per place</legend>
                <p className="muted small">Default: the case's noise for that place plus the conditions and onlookers.</p>
                {t.stages.map(s => {
                  const own = adv.stage_noise?.[s.id]
                  const def = placeNoise(s)
                  return (
                    <label key={s.id} className="field">
                      <span>{s.label}: {own != null ? pct(own) : `default (${pct(def)})`}</span>
                      <div className="override">
                        <input type="range" min={0} max={1} step={0.05} value={own ?? def} onChange={e => setStageNoise(s.id, Number(e.target.value))} />
                        <button type="button" className="link" disabled={own == null} onClick={() => setStageNoise(s.id, null)}>Default</button>
                      </div>
                    </label>
                  )
                })}
              </fieldset>
            )}

            <fieldset>
              <legend>Repeatability</legend>
              <label className="field narrow">
                <span>Seed (blank = {edit.scenarioId ? 'keep current seed' : 'random'})</span>
                <input inputMode="numeric" value={seedText} onChange={e => setSeedText(e.target.value)} aria-invalid={!seedValid} />
                {!seedValid && <small className="issue-error">Seed must be a whole number.</small>}
              </label>
              <small className="muted">Fixes the order of the bystander's lines and where background figures stand, so a run can be repeated exactly.</small>
            </fieldset>
          </>}

          {step.id === 'review' && (
            preview && errors.length === 0
              ? <><p className="muted">This is the scenario the server generates from your choices. Nothing is saved until you save.</p><DefinitionView def={preview} /></>
              : <p className="muted">Fix the problems listed under Checks to see the generated scenario.</p>
          )}

          <div className="actions">
            <button type="button" disabled={at === 0} onClick={() => setStepId(steps[at - 1].id)}>Back</button>
            {at < steps.length - 1
              ? <button type="button" className="primary" onClick={() => setStepId(steps[at + 1].id)}>Next: {steps[at + 1].label}</button>
              : <button type="button" className="primary" onClick={runSave} disabled={!canSave}>{save.pending ? 'Saving…' : edit.scenarioId ? 'Save as new version' : 'Save to my scenarios'}</button>}
          </div>
        </form>

        <aside className="side">
          <div className="sticky">
            <p><KindBadge kind={t.kind} stages={t.stages.length} /></p>
            <p className="small"><strong>{t.label}</strong></p>
            <h3>Checks {validating && <span className="muted small">checking…</span>}</h3>
            <ErrorText error={validateError} />
            {!validating && !issues.length && !validateError && <p className="ok">No problems found.</p>}
            <IssueList issues={[...errors, ...warnings]} />
            {preview && errors.length === 0 && <>
              <h4>What this produces</h4>
              <dl className="kv small">
                {preview.journey
                  ? <><dt>Noise per place</dt><dd>{preview.journey.stages.map(s => pct(s.noise)).join(' → ')}</dd></>
                  : <><dt>Room noise</dt><dd>{pct(preview.environment.ambient_level)}</dd></>}
                <dt>Background figures</dt><dd>{preview.environment.crowd.figures.length}</dd>
                <dt>Coaching</dt><dd>{HINT_LABEL[preview.difficulty.hint_policy]}</dd>
                <dt>At the start</dt><dd>{preview.resources.filter(r => r.available).length} of {preview.resources.length} items</dd>
                <dt>Deliverable later</dt><dd>{preview.resources.filter(r => r.deliverable).length}</dd>
                {preview.assessment.dimensions.map(d => <span key={d.id} className="kv-row"><dt>{d.title}</dt><dd>{d.achievable_max} of {d.max_score} points earnable</dd></span>)}
              </dl>
            </>}
            <h4>Fixed by the case</h4>
            <p className="muted small">No scenario setting can change these:</p>
            <ul className="fixed">
              {t.fixed_facts.map(f => <li key={f}>{f}</li>)}
              {journey && <li>the places, their order and the team at each</li>}
            </ul>
            <div className="actions">
              <button type="button" className="primary" onClick={runSave} disabled={!canSave}>
                {save.pending ? 'Saving…' : edit.scenarioId ? 'Save as new version' : 'Save to my scenarios'}
              </button>
            </div>
            <ErrorText error={save.error} />
            <IssueList issues={save.issues} />
          </div>
        </aside>
      </div>

    </div>
  )
}
