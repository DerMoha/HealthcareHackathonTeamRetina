import { useState } from 'react'
import type { ScenarioConfig } from './api'
import Author from './Author'
import Library from './Library'
import Director from './Director'
import DebriefTab from './Debrief'

type Tab = 'author' | 'library' | 'director' | 'debrief'
const TABS: [Tab, string][] = [['author', 'Author'], ['library', 'Library'], ['director', 'Director'], ['debrief', 'Debrief']]

export interface EditRequest { key: number; scenarioId: string | null; config: ScenarioConfig | null }

export default function App() {
  const [tab, setTab] = useState<Tab>('library')
  // `key` remounts the Author form when Library asks to edit something else.
  const [edit, setEdit] = useState<EditRequest>({ key: 0, scenarioId: null, config: null })
  const [debriefId, setDebriefId] = useState('')
  const [libraryVersion, setLibraryVersion] = useState(0)

  return (
    <div className="app">
      <header className="topbar">
        <h1>MedSim Studio</h1>
        <nav role="tablist" aria-label="Sections">
          {TABS.map(([id, label]) => (
            <button key={id} role="tab" aria-selected={tab === id} className={tab === id ? 'tab active' : 'tab'}
              onClick={() => setTab(id)}>{label}</button>
          ))}
        </nav>
      </header>
      <main>
        {/* Tabs stay mounted so a half-written scenario or live socket survives switching. */}
        <section hidden={tab !== 'author'}>
          <Author key={edit.key} edit={edit}
            onSaved={() => { setLibraryVersion(v => v + 1); setTab('library') }}
            onNew={() => setEdit(e => ({ key: e.key + 1, scenarioId: null, config: null }))} />
        </section>
        <section hidden={tab !== 'library'}>
          <Library version={libraryVersion} visible={tab === 'library'}
            onEdit={(scenarioId, config) => { setEdit(e => ({ key: e.key + 1, scenarioId, config })); setTab('author') }} />
        </section>
        <section hidden={tab !== 'director'}>
          <Director active={tab === 'director'} onDebrief={id => { setDebriefId(id); setTab('debrief') }} />
        </section>
        <section hidden={tab !== 'debrief'}>
          <DebriefTab sessionId={debriefId} setSessionId={setDebriefId} visible={tab === 'debrief'} />
        </section>
      </main>
    </div>
  )
}
