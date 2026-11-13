import { useState } from 'react'
import type { ScenarioConfig } from './api'
import Author from './Author'
import Library from './Library'
import Director from './Director'
import DebriefTab from './Debrief'
import Overview from './Overview'
import Marketplace from './Marketplace'

export type Page = 'overview' | 'mine' | 'downloaded' | 'marketplace' | 'generator' | 'director' | 'debrief'
const MENU: { title: string; items: [Page, string][] }[] = [
  { title: 'Home', items: [['overview', 'Overview']] },
  { title: 'Scenarios', items: [['mine', 'My scenarios'], ['downloaded', 'Downloaded'], ['marketplace', 'Marketplace'], ['generator', 'Scenario generator']] },
  { title: 'Sessions', items: [['director', 'Live director'], ['debrief', 'Debrief']] },
]

export interface EditRequest { key: number; scenarioId: string | null; config: ScenarioConfig | null }

export default function App() {
  const [page, setPage] = useState<Page>('overview')
  // `key` remounts the generator when another page asks to edit something else.
  const [edit, setEdit] = useState<EditRequest>({ key: 0, scenarioId: null, config: null })
  const [debriefId, setDebriefId] = useState('')
  const [libraryVersion, setLibraryVersion] = useState(0)
  const [focus, setFocus] = useState<string | null>(null)
  const changed = () => setLibraryVersion(v => v + 1)
  const onEdit = (scenarioId: string, config: ScenarioConfig) => { setEdit(e => ({ key: e.key + 1, scenarioId, config })); setPage('generator') }
  const open = (id: string, downloaded: boolean) => { setFocus(id); setPage(downloaded ? 'downloaded' : 'mine') }

  return (
    <div className="shell">
      <aside className="sidebar">
        <h1>MedSim Studio</h1>
        <nav aria-label="Sections">
          {MENU.map(group => (
            <div key={group.title} className="menu-group">
              <div className="menu-title">{group.title}</div>
              {group.items.map(([id, label]) => (
                <button key={id} type="button" aria-current={page === id ? 'page' : undefined}
                  className={page === id ? 'menu-item active' : 'menu-item'} onClick={() => setPage(id)}>{label}</button>
              ))}
            </div>
          ))}
        </nav>
      </aside>
      <main>
        {/* Pages stay mounted so a half-written scenario or the live socket survives switching. */}
        <section hidden={page !== 'overview'}>
          <Overview visible={page === 'overview'} version={libraryVersion} go={setPage} onOpen={open} onEdit={onEdit}
            onDebrief={id => { setDebriefId(id); setPage('debrief') }} />
        </section>
        <section hidden={page !== 'mine'}>
          <Library scope="mine" version={libraryVersion} visible={page === 'mine'} focus={focus} onEdit={onEdit} onChanged={changed} onOpen={open} />
        </section>
        <section hidden={page !== 'downloaded'}>
          <Library scope="downloaded" version={libraryVersion} visible={page === 'downloaded'} focus={focus} onEdit={onEdit} onChanged={changed} onOpen={open} />
        </section>
        <section hidden={page !== 'marketplace'}>
          <Marketplace visible={page === 'marketplace'} version={libraryVersion}
            onDownloaded={id => { changed(); open(id, true) }} />
        </section>
        <section hidden={page !== 'generator'}>
          <Author key={edit.key} edit={edit}
            onSaved={id => { changed(); open(id, false) }}
            onNew={() => setEdit(e => ({ key: e.key + 1, scenarioId: null, config: null }))} />
        </section>
        <section hidden={page !== 'director'}>
          <Director active={page === 'director'} onDebrief={id => { setDebriefId(id); setPage('debrief') }} />
        </section>
        <section hidden={page !== 'debrief'}>
          <DebriefTab sessionId={debriefId} setSessionId={setDebriefId} visible={page === 'debrief'} />
        </section>
      </main>
    </div>
  )
}
