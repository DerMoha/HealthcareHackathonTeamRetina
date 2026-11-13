import { useCallback, useState } from 'react'
import { ApiError, type Issue, type ReviewState } from './api'

const REVIEW_LABEL: Record<ReviewState, string> = {
  draft: 'Draft',
  experimental: 'Experimental',
  clinician_reviewed: 'Clinician-reviewed',
}

export function ReviewBadge({ state }: { state: ReviewState }) {
  return <span className={`badge badge-${state}`}>{REVIEW_LABEL[state] ?? state}</span>
}

export function ErrorText({ error, onDismiss }: { error: string | null; onDismiss?: () => void }) {
  if (!error) return null
  return (
    <div className="notice notice-error" role="alert">
      <span>{error}</span>
      {onDismiss && <button type="button" className="link" onClick={onDismiss}>Dismiss</button>}
    </div>
  )
}

export function IssueList({ issues }: { issues: Issue[] }) {
  if (!issues.length) return null
  return (
    <ul className="issues">
      {issues.map((i, n) => (
        <li key={n} className={`issue issue-${i.severity}`}>
          <span className="issue-field">{i.field}</span> {i.message}
        </li>
      ))}
    </ul>
  )
}

/** Wraps an async action with pending + error state. */
export function useAction() {
  const [pending, setPending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [issues, setIssues] = useState<Issue[]>([])
  const run = useCallback(async <T,>(fn: () => Promise<T>): Promise<T | undefined> => {
    setPending(true); setError(null); setIssues([])
    try { return await fn() }
    catch (e) {
      setError(e instanceof Error ? e.message : String(e))
      if (e instanceof ApiError) setIssues(e.issues)
    } finally { setPending(false) }
  }, [])
  return { pending, error, issues, run, clearError: () => setError(null) }
}

export function fmtTime(iso: string): string {
  const d = new Date(iso)
  return isNaN(d.getTime()) ? iso : d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })
}
export function fmtDate(iso: string): string {
  const d = new Date(iso)
  return isNaN(d.getTime()) ? iso : d.toLocaleString([], { dateStyle: 'medium', timeStyle: 'short' })
}

export function Meter({ value, label }: { value: number; label: string }) {
  const pct = Math.round(Math.max(0, Math.min(1, value)) * 100)
  return (
    <div className="meter" role="meter" aria-label={label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={pct}>
      <div className="meter-fill" style={{ width: `${pct}%` }} />
      <span className="meter-text">{pct}%</span>
    </div>
  )
}
