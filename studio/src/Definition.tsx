import type { ScenarioDefinition } from './api'

/** Readable summary of a ScenarioDefinition plus the raw JSON. Used by Author (preview) and Library (details). */
export default function DefinitionView({ def }: { def: ScenarioDefinition }) {
  const env = def.environment
  return (
    <div className="definition">
      <dl className="kv">
        <dt>Seed</dt><dd>{def.seed}</dd>
        <dt>Launch code</dt><dd><code>{def.code}</code></dd>
        <dt>Environment</dt><dd>{env.label} (ambient noise {Math.round(env.ambient_level * 100)}%)<br /><span className="muted">{env.brief}</span></dd>
        <dt>Crowd</dt><dd>{env.crowd.label}, {env.crowd.figures.length} figure{env.crowd.figures.length === 1 ? '' : 's'}</dd>
        <dt>Difficulty</dt><dd>{def.difficulty.label}: {def.difficulty.description}</dd>
        <dt>Hint policy</dt><dd><code>{def.difficulty.hint_policy}</code>, {def.difficulty.hints.length} hint{def.difficulty.hints.length === 1 ? '' : 's'}</dd>
      </dl>

      <h4>Resources</h4>
      <table className="table compact">
        <thead><tr><th>Item</th><th>Kind</th><th>Available</th><th>Deliverable later</th><th>Reason</th></tr></thead>
        <tbody>
          {def.resources.map(r => (
            <tr key={r.id}>
              <td>{r.label}</td><td>{r.kind.replace('_', ' ')}</td>
              <td>{r.available ? 'Yes' : 'No'}</td><td>{r.deliverable ? 'Yes' : 'No'}</td>
              <td>{r.unsupported_reason ?? ''}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <h4>Companions</h4>
      <ul className="plain">
        <li>Bystander: {def.companions.bystander
          ? `${def.companions.bystander.name} (${def.companions.bystander.role_label}), starts ${def.companions.bystander.mood}, speaks about every ${def.companions.bystander.interject_every_s} s`
          : 'none'}</li>
        <li>Teammate: {def.companions.teammate.name} ({def.companions.teammate.role_label}), {def.companions.teammate.present ? 'present from the start' : 'not present at the start'}</li>
      </ul>

      {def.difficulty.hints.length > 0 && (
        <details>
          <summary>Coaching hints ({def.difficulty.hints.length})</summary>
          <ol>{def.difficulty.hints.map(h => <li key={h.id}>{h.text}</li>)}</ol>
        </details>
      )}

      <h4>Assessment</h4>
      <table className="table compact">
        <thead><tr><th>Dimension</th><th>Max</th><th>Achievable here</th></tr></thead>
        <tbody>
          {def.assessment.dimensions.map(d => (
            <tr key={d.id}><td>{d.title}</td><td>{d.max_score}</td><td>{d.achievable_max}</td></tr>
          ))}
        </tbody>
      </table>
      {def.assessment.dimensions.flatMap(d => d.not_assessable.map(n => (
        <p key={d.id + n.id} className="issue issue-warning"><strong>{n.label}</strong> ({n.points} pts, not assessable): {n.reason}</p>
      )))}
      <p className="muted">{def.assessment.note}</p>

      <h4>Clinical rules</h4>
      <p>{def.clinical_rules.statement}</p>
      {def.clinical_rules.constraints.length > 0 && (
        <ul>{def.clinical_rules.constraints.map((c, i) => <li key={i}>{c}</li>)}</ul>
      )}

      <details>
        <summary>Raw JSON</summary>
        <pre className="json">{JSON.stringify(def, null, 2)}</pre>
      </details>
    </div>
  )
}
