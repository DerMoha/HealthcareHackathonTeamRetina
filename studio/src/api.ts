// Typed client for the MedSim Studio API. Types mirror docs/studio-api.md.

export type ReviewState = 'draft' | 'experimental' | 'clinician_reviewed'
export type HintPolicy = 'auto' | 'on_request' | 'off'

export interface Narrative {
  description: string
  patient_personality: string
  bystander_lines: string[]
  source: 'template' | 'instructor' | 'llm'
}

export interface ScenarioConfig {
  template_id: string
  title: string
  environment: string
  difficulty: string
  crowdedness: string
  tools: string[]
  bystander: string
  teammate: string
  learning_objectives: string[]
  narrative: Narrative
  /** Advanced mode only; every field optional. Absent = what the basic choices imply. */
  advanced?: Advanced
  seed: number | null
}

export interface Advanced {
  hint_policy?: HintPolicy | null
  interject_every_s?: number | null
  crowd_figures?: number | null
  /** Journey cases: place id -> noise 0..1. */
  stage_noise?: Record<string, number>
}

export type CaseKind = 'single' | 'journey'
/** A place of a journey case, in the case's fixed order. */
export interface Stage { id: string; label: string; setting: string; team: string[]; noise: number; actions: number }

export interface Issue { field: string; severity: 'error' | 'warning'; message: string }
export interface Validation { valid: boolean; issues: Issue[] }

export interface Choice { id: string; label: string }
export interface Dimension {
  id: 'core' | 'management' | 'fitting'
  title: string
  max_score: number
  achievable_max: number
  not_assessable: { id: string; label: string; points: number; reason: string }[]
}
export interface Template {
  template_id: string
  case_id: string
  label: string
  summary: string
  clinical_review: string
  environments: { id: string; label: string; brief: string; ambient_level: number; unsupported_equipment: string[] }[]
  unsupported_environments: { id: string; label: string; reason: string }[]
  equipment: { id: string; label: string; kind: string }[]
  difficulties: { id: string; label: string; hint_policy: HintPolicy; description: string }[]
  crowdedness: { id: string; label: string; noise: number; figures: number }[]
  bystander_behaviors: Choice[]
  teammate_behaviors: Choice[]
  learning_objectives: (Choice & { needs_kind?: string })[]
  hints: string[]
  dimensions: Dimension[]
  kind: CaseKind
  stages: Stage[]
  patient: { name: string; age: number }
  fixed_facts: string[]
}

export interface Assist {
  source: 'llm' | 'demo' | 'template'
  model: string | null
  description: string
  patient_personality: string
  bystander_lines: string[]
  learning_objectives: string[]
  notes: string[]
  requires_review: boolean
}

export interface Review {
  state: ReviewState
  reviewer_name: string | null
  reviewer_role: string | null
  reviewed_at: string | null
  notes: string | null
}

export interface Resource {
  id: string
  label: string
  kind: string
  available: boolean
  deliverable: boolean
  unsupported_reason: string | null
}

export interface Bystander {
  name: string
  role_label: string
  mood: 'calm' | 'anxious'
  lines: { calm: string[]; anxious: string[] }
  interject_every_s: number
}

export interface ScenarioDefinition {
  schema_version: number
  scenario_id: string
  version: number
  code: string
  title: string
  created_at: string
  source_template: { template_id: string; case_id: string; case_schema_version: number }
  seed: number
  review: Review
  published: boolean
  config: ScenarioConfig
  environment: {
    id: string; label: string; brief: string; setting_context: string; ambient_level: number
    crowd: { id: string; label: string; figures: { angle_deg: number; distance_m: number }[] }
  }
  resources: Resource[]
  companions: {
    bystander: Bystander | null
    teammate: { name: string; role_label: string; present: boolean }
  }
  difficulty: { id: string; label: string; hint_policy: HintPolicy; description: string; hints: { id: string; text: string }[] }
  clinical_rules: { case_id: string; immutable_facts: string[]; findings_sha256: string; statement: string; constraints: string[] }
  assessment: { dimensions: Dimension[]; learning_objectives: Choice[]; note: string }
  narrative: { description: string; patient_personality: string; source: string; ai_generated: boolean }
  journey: { stages: Stage[] } | null
  origin: Origin | null
}

export interface Origin { duplicated_from?: string; imported_from?: string; downloaded_from?: string; code?: string; version?: number; claimed_review_state?: string }
/** Came from somewhere else (marketplace or a file), as opposed to created or duplicated here. */
export const isDownloaded = (o: Origin | null) => !!o && (o.downloaded_from != null || o.imported_from !== undefined)

export interface PublishedRow {
  code: string; scenario_id: string; version: number; title: string; description: string
  review_state: ReviewState; environment: string; difficulty: string; crowdedness: string
  kind?: CaseKind; stages?: string[]
}

export interface LibraryRow {
  scenario_id: string
  code: string
  title: string
  version: number
  versions: number
  review_state: ReviewState
  published_version: number | null
  template_id: string
  environment: string
  difficulty: string
  crowdedness: string
  created_at: string
  ai_generated: boolean
  origin: Origin | null
  kind?: CaseKind
  stages?: string[]
}
export interface VersionRow { version: number; created_at: string; review_state: ReviewState; published: boolean }

export interface CrowdFigure { angle_deg: number; distance_m: number }
export interface ScenarioRuntime {
  scenario_id: string; version: number; code: string; title: string; review_state: ReviewState; seed: number
  environment_id: string; environment_label: string; difficulty: string; hint_policy: HintPolicy
  noise_level: number; crowd_figures: CrowdFigure[]
  bystander: null | { name: string; role_label: string; mood: 'calm' | 'anxious'; lines: { calm: string[]; anxious: string[] }; interject_every_s: number }
  teammate: { name: string; role_label: string; present: boolean }
  equipment: { id: string; label: string; kind: string; available: boolean }[]
}

export interface ActiveSession {
  session_id: string; started_at: string; title: string; code: string; runtime_connected: boolean; submitted: boolean
}

export interface Intervention {
  seq: number; event_id: string; kind: string; label: string; params: Record<string, unknown>; at: string
  line: null | { speaker: string; text: string }
  voice_context: string
  acknowledged: boolean
  ack_detail: string | null
}
export interface DirectorEventInfo {
  kind: string; label: string; enabled: boolean; reason: string | null
  param?: string; options?: Choice[]
}
export interface DirectorState {
  session_id: string; started_at: string; runtime_connected: boolean
  scenario: ScenarioRuntime
  events: DirectorEventInfo[]
  interventions: Intervention[]
  hints: { seq: number; id: string; text: string; at: string }[]
  activity: Record<string, number | boolean>
}

export interface Score {
  score: number; max_score: number; achievable_max?: number
  not_assessable?: { id: string; label: string; points: number; reason: string }[]
}
export interface Debrief {
  session_id: string
  case_id: string
  diagnosis_submitted: string | null
  scenario: null | {
    scenario_id: string; version: number; code: string; title: string; review_state: ReviewState
    template_id: string; seed: number; environment: string; crowdedness: string; difficulty: string
    bystander: string; teammate: string; learning_objectives: Choice[]
  }
  resources: { id: string; label: string; kind: string; available_at_start: boolean; delivered_at_seq: number | null; available_at_end: boolean; used: boolean }[]
  interventions: Intervention[]
  hints: { seq: number; id: string; text: string; at: string }[]
  timeline: { seq: number; type: string; label: string }[]
  scores: Record<string, Score>
  interpretation: string[]
  // The existing Feedback model (backend/app/models.py); only the fields this UI shows.
  feedback: {
    summary: string
    diagnostic_assessment: { verdict: 'correct' | 'partial' | 'incorrect' | 'not_submitted'; explanation: string; expected: string | null }
    strengths: string[]
    missed: string[]
  }
}

/** Error with the server's `detail` as text and, for a rejected scenario, its issues. */
export class ApiError extends Error {
  constructor(message: string, public status: number, public issues: Issue[] = []) { super(message) }
}

async function call<T>(method: string, path: string, body?: unknown): Promise<T> {
  let res: Response
  try {
    res = await fetch(path, {
      method,
      headers: body === undefined ? undefined : { 'content-type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    })
  } catch {
    throw new ApiError('Cannot reach the server.', 0)
  }
  const text = await res.text()
  let data: unknown = null
  try { data = text ? JSON.parse(text) : null } catch { /* non-JSON body */ }
  if (!res.ok) throw toError(res.status, data, text)
  return data as T
}

function toError(status: number, data: unknown, text: string): ApiError {
  const detail = (data as { detail?: unknown } | null)?.detail
  if (typeof detail === 'string') return new ApiError(detail, status)
  if (Array.isArray(detail)) {
    // FastAPI/pydantic body validation: [{loc, msg}]. Shown as issues so the form can display them.
    const issues = detail.map((d: { loc?: unknown[]; msg?: string }): Issue => ({
      field: (d.loc ?? []).filter(p => p !== 'body').join('.') || 'body',
      severity: 'error',
      message: d.msg ?? 'invalid',
    }))
    return new ApiError('The request was rejected.', status, issues)
  }
  if (detail && typeof detail === 'object') {
    const d = detail as { message?: string; issues?: Issue[] }
    return new ApiError(d.message ?? 'The request was rejected.', status, d.issues ?? [])
  }
  return new ApiError(text || `HTTP ${status}`, status)
}

export const api = {
  catalog: () => call<Template[]>('GET', '/studio/catalog'),
  validate: (c: ScenarioConfig) => call<Validation>('POST', '/studio/validate', c),
  preview: (c: ScenarioConfig) => call<ScenarioDefinition>('POST', '/studio/preview', c),
  assist: (b: { template_id: string; environment: string; difficulty: string; crowdedness: string; tools: string[]; bystander: string; focus: string }) =>
    call<Assist>('POST', '/studio/assist', b),

  library: () => call<LibraryRow[]>('GET', '/studio/scenarios'),
  scenario: (id: string) => call<ScenarioDefinition>('GET', `/studio/scenarios/${id}`),
  versions: (id: string) => call<VersionRow[]>('GET', `/studio/scenarios/${id}/versions`),
  create: (c: ScenarioConfig) => call<ScenarioDefinition>('POST', '/studio/scenarios', c),
  update: (id: string, c: ScenarioConfig) => call<ScenarioDefinition>('PUT', `/studio/scenarios/${id}`, c),
  duplicate: (id: string) => call<ScenarioDefinition>('POST', `/studio/scenarios/${id}/duplicate`),
  setState: (id: string, state: 'draft' | 'experimental') => call<ScenarioDefinition>('POST', `/studio/scenarios/${id}/state`, { state }),
  // Only the attested clinician form in Library.tsx calls this; `attestation: true` is a type-level requirement.
  review: (id: string, b: { reviewer_name: string; reviewer_role: string; notes: string; attestation: true }) =>
    call<ScenarioDefinition>('POST', `/studio/scenarios/${id}/review`, b),
  publish: (id: string) => call<ScenarioDefinition>('POST', `/studio/scenarios/${id}/publish`),
  unpublish: (id: string) => call<ScenarioDefinition>('POST', `/studio/scenarios/${id}/unpublish`),
  import: (def: unknown) => call<ScenarioDefinition>('POST', '/studio/import', def),
  published: () => call<PublishedRow[]>('GET', '/scenarios/published'),
  download: (code: string) => call<ScenarioDefinition>('POST', `/studio/marketplace/${encodeURIComponent(code)}/download`),

  active: () => call<ActiveSession[]>('GET', '/sessions/active'),
  debrief: (id: string) => call<Debrief>('GET', `/sessions/${encodeURIComponent(id)}/debrief`),
}

export function directorSocketUrl(id: string): string {
  const proto = location.protocol === 'https:' ? 'wss' : 'ws'
  return `${proto}://${location.host}/ws/sessions/${encodeURIComponent(id)}?role=director`
}
