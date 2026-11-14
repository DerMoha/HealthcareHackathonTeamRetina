/* Pitch-only Studio (?pitch=1): static, backend-free screens for the jury screenshots.
 * Pages: ?pitch=1&page=generator|author|publish|marketplace&v=a|b. The real app is untouched. */
import type { ReactNode } from 'react'
import './pitch.css'

const q = new URLSearchParams(location.search)
const page = q.get('page') ?? 'generator'
const v = q.get('v') === 'b' ? 'b' : 'a'
const img = (n: string) => `pitch/${n}`
const shot = (n: string) => `pitch/shots/${n}.jpg`

/* ---------- icons (24px stroke) ---------- */
const P: Record<string, ReactNode> = {
  home: <path d="M4 11l8-7 8 7v9h-5v-6H9v6H4z" />,
  mix: <><path d="M5 4v16M12 4v16M19 4v16" /><circle cx="5" cy="9" r="2.2" /><circle cx="12" cy="15" r="2.2" /><circle cx="19" cy="7" r="2.2" /></>,
  spark: <path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8zM18.5 15.5l.8 2.2 2.2.8-2.2.8-.8 2.2-.8-2.2-2.2-.8 2.2-.8z" />,
  folder: <path d="M3 6h6l2 2h10v11H3z" />,
  store: <><path d="M4 9l1.5-5h13L20 9" /><path d="M4 9h16v11H4z" /><path d="M9 20v-6h6v6" /></>,
  live: <><circle cx="12" cy="12" r="2.5" /><path d="M7.5 7.5a6.4 6.4 0 000 9M16.5 7.5a6.4 6.4 0 010 9M4.6 4.6a10.5 10.5 0 000 14.8M19.4 4.6a10.5 10.5 0 010 14.8" /></>,
  chart: <path d="M4 20V10M10 20V4M16 20v-7M22 20H2" />,
  search: <><circle cx="11" cy="11" r="6.5" /><path d="M16 16l4.5 4.5" /></>,
  goggles: <path d="M3 9.5C3 7.6 4.6 6.5 7 6.5h10c2.4 0 4 1.1 4 3v3.2c0 2.3-1.6 4.3-4 4.3-1.6 0-2.6-.8-3.3-2-.5-.8-1-1.2-1.7-1.2s-1.2.4-1.7 1.2c-.7 1.2-1.7 2-3.3 2-2.4 0-4-2-4-4.3z" />,
  check: <path d="M5 12.5l4.2 4.2L19 7" />,
  clock: <><circle cx="12" cy="12" r="8.5" /><path d="M12 7.5V12l3 2" /></>,
  users: <><circle cx="9" cy="8.5" r="3.2" /><path d="M3 19.5c.6-3.3 3-5 6-5s5.4 1.7 6 5" /><circle cx="17" cy="9.5" r="2.5" /><path d="M16.5 14.6c2.4.2 4 1.8 4.5 4.4" /></>,
  bolt: <path d="M13 3L5 13.5h6L10 21l8-10.5h-6z" />,
  star: <path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.9L12 17l-5.2 2.7 1-5.9-4.3-4.1 5.9-.8z" />,
  down: <><path d="M12 4v11M7 10.5l5 5 5-5" /><path d="M5 20h14" /></>,
  send: <path d="M4 12l16-8-6 16-3-7z" />,
  shield: <><path d="M12 3l7.5 3v5.5c0 4.6-3.2 8.2-7.5 9.5-4.3-1.3-7.5-4.9-7.5-9.5V6z" /><path d="M8.5 12l2.5 2.5 4.5-4.5" /></>,
  sun: <><circle cx="12" cy="12" r="4" /><path d="M12 2.5v2.5M12 19v2.5M2.5 12H5M19 12h2.5M5.3 5.3l1.8 1.8M16.9 16.9l1.8 1.8M5.3 18.7l1.8-1.8M16.9 7.1l1.8-1.8" /></>,
  moon: <path d="M19.5 14.5A8 8 0 019.5 4.5a8 8 0 1010 10z" />,
  rain: <><path d="M7 15a4.5 4.5 0 01-.6-9 5.5 5.5 0 0110.7 1.4A3.8 3.8 0 0117 15z" /><path d="M8 18l-1 2.5M12 18l-1 2.5M16 18l-1 2.5" /></>,
  cloud: <path d="M7 18a4.5 4.5 0 01-.6-9 5.5 5.5 0 0110.7 1.4A3.8 3.8 0 0117 18z" />,
  dusk: <><path d="M3 18h18M6 14.5a6 6 0 0112 0" /><path d="M12 4v3M4.9 7.9l2 2M19.1 7.9l-2 2" /></>,
  plus: <path d="M12 5v14M5 12h14" />,
  tool: <path d="M14.5 6.5a4 4 0 00-5.3 5.1L4 16.8 7.2 20l5.2-5.2a4 4 0 005.1-5.3l-2.6 2.6-2.4-.6-.6-2.4z" />,
  doc: <><path d="M6 3h8l4 4v14H6z" /><path d="M14 3v4h4M9 12h6M9 16h6" /></>,
  globe: <><circle cx="12" cy="12" r="8.5" /><path d="M3.5 12h17M12 3.5c2.4 2.6 3.5 5.4 3.5 8.5s-1.1 5.9-3.5 8.5c-2.4-2.6-3.5-5.4-3.5-8.5s1.1-5.9 3.5-8.5z" /></>,
  mic: <><rect x="9" y="3" width="6" height="11" rx="3" /><path d="M5.5 11a6.5 6.5 0 0013 0M12 17.5V21" /></>,
  arrow: <path d="M5 12h14M13 6l6 6-6 6" />,
  x: <path d="M6 6l12 12M18 6L6 18" />,
  layers: <path d="M12 3l9 5-9 5-9-5zM3 13l9 5 9-5" />,
}
const I = ({ n, s = 18, cls }: { n: string; s?: number; cls?: string }) => (
  <svg className={`ico ${cls ?? ''}`} width={s} height={s} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={1.7} strokeLinecap="round" strokeLinejoin="round" aria-hidden>{P[n]}</svg>
)

/* ---------- shell ---------- */
const NAV: [string, string, string][] = [
  ['overview', 'home', 'Overview'],
  ['generator', 'mix', 'Scenario generator'],
  ['author', 'spark', 'AI author'],
  ['library', 'folder', 'My scenarios'],
  ['marketplace', 'store', 'Marketplace'],
  ['director', 'live', 'Live sessions'],
  ['debrief', 'chart', 'Debriefs'],
]

function Shell({ active, title, crumb, children, actions }: { active: string; title: string; crumb: string; children: ReactNode; actions?: ReactNode }) {
  return (
    <div className={`ps ps-${v === 'b' && page !== 'publish' ? 'dark' : 'light'}`}>
      <aside className="ps-side">
        <div className="ps-brand">
          <span className="ps-mark"><svg viewBox="0 0 32 32" width="30" height="30"><rect width="32" height="32" rx="9" fill="currentColor" /><path d="M4 18h6l2.5-6 4 11 3-8 1.5 3H28" fill="none" stroke="var(--side)" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" /></svg></span>
          <span><b>MedSim</b> Studio</span>
        </div>
        <nav>
          {NAV.map(([id, ic, label]) => (
            <a key={id} className={id === active ? 'on' : ''}><I n={ic} />{label}{id === 'library' && <em>14</em>}{id === 'director' && <em className="live">2</em>}</a>
          ))}
        </nav>
        <div className="ps-devices">
          <div className="ps-devices-h">Headsets</div>
          <div className="dev"><I n="goggles" /><span>Sim Lab 2 · Bay A<small>Ready</small></span><i className="dot ok" /></div>
          <div className="dev"><I n="goggles" /><span>Sim Lab 2 · Bay B<small>In session · Jordan</small></span><i className="dot busy" /></div>
          <div className="dev dim"><I n="goggles" /><span>Skills Hub · 3<small>Charging 64%</small></span><i className="dot" /></div>
        </div>
        <div className="ps-me">
          <span className="av av-me">EH</span>
          <span>Dr Elena Hart<small>Clinical skills lead · Northgate Medical School</small></span>
        </div>
      </aside>
      <div className="ps-main">
        <header className="ps-top">
          <div>
            <div className="crumb">{crumb}</div>
            <h1>{title}</h1>
          </div>
          <div className="ps-top-r">
            <label className="ps-search"><I n="search" s={16} /><span>Search scenarios, protocols, colleagues</span><kbd>⌘K</kbd></label>
            {actions}
          </div>
        </header>
        <div className="ps-body">{children}</div>
      </div>
    </div>
  )
}

/* ---------- generator ---------- */
type Env = { id: string; name: string; pic: string; note: string }
const ENVS: Env[] = [
  { id: 'clinic', name: 'Clinic room', pic: img('webstudio-cover-wrist-talk.jpg'), note: 'Outpatient, X-ray on site' },
  { id: 'scan', name: 'Antenatal scan room', pic: img('webstudio-cover-us-card.jpg'), note: 'Ultrasound, couch, monitor' },
  { id: 'road', name: 'Roadside', pic: img('webstudio-cover-rt-splint.jpg'), note: 'Urban junction, traffic' },
  { id: 'forest', name: 'Forest trail', pic: img('webstudio-forest-trail.jpg'), note: 'Remote, 40 min to road' },
  { id: 'amb', name: 'Ambulance', pic: shot('rt-04-ambulance'), note: 'Moving, noise, monitor' },
  { id: 'resus', name: 'Resus bay', pic: shot('rt-05-resus'), note: 'Trauma team, imaging' },
  { id: 'home', name: "Patient's home", pic: img('webstudio-home.jpg'), note: 'Living room, family' },
]

type Gen = {
  title: string; cover: string; envs: string[]; crowd: number; stress: number; time: string; weather: string
  persona: { init: string; name: string; age: number; sex: string; mood: string; lang: string; line: string }
  team: [string, string, string][]; diff: string; objectives: [string, boolean][]; protocol: string
  minutes: number; items: number; scheme: [string, number][]; face: string[]; crowdLabel: string; stressLabel: string; disruptors: [string, boolean][]
}
const GEN: Record<'a' | 'b', Gen> = {
  a: {
    title: 'Cyclist versus car: roadside to resus', cover: img('webstudio-cover-rt-crew.jpg'), envs: ['road', 'amb', 'resus'],
    crowd: 6, stress: 4, time: 'Dusk', weather: 'Rain',
    persona: { init: 'J', name: 'Jordan', age: 34, sex: 'Male', mood: 'Frightened', lang: 'English', line: 'Bicycle courier, hit by a car pulling out. Deformed right forearm, bleeding wound.' },
    team: [['Sam', 'Paramedic', 'crew'], ['Lena', 'Technician', 'crew'], ['Dr Omar', 'ED consultant', 'crew'], ['Priya', 'Trauma nurse', 'crew']],
    diff: 'Final-year', protocol: 'cabcde',
    objectives: [['Scene safety and <C>ABCDE primary survey', true], ['Control catastrophic haemorrhage', true], ['Splint and reassess neurovascular status', true], ['ATMIST pre-alert and handover', true], ['Analgesia choice and dosing', false]],
    minutes: 24, items: 32, scheme: [['<C> Haemorrhage', 4], ['A Airway, C-spine', 3], ['B Breathing', 4], ['C Circulation', 5], ['D Disability', 3], ['E Exposure', 3], ['ATMIST handover', 6], ['Team and bystanders', 4]], crowdLabel: 'Driver, two pedestrians, a shop owner, a cyclist friend, a man filming',
    stressLabel: 'about every 15 s',
    disruptors: [['Bystanders question your decisions', true], ['Driver keeps apologising', true], ['Phone camera filming you', true], ['Siren and traffic noise', true]],
    face: ['The driver insists Jordan "just needs to stand up"', 'A bystander films and asks why you are not moving him', 'Sam asks for your call on the tourniquet at 02:10', 'Pre-alert to resus by radio, ATMIST format'],
  },
  b: {
    title: 'Mid-pregnancy scan: Sarah, 20 weeks', cover: img('webstudio-cover-us-hero.jpg'), envs: ['scan'],
    crowd: 1, stress: 1, time: 'Day', weather: 'Clear',
    persona: { init: 'S', name: 'Sarah', age: 31, sex: 'Female', mood: 'Nervous', lang: 'English', line: 'Primary school teacher, first pregnancy, 20 weeks. Partner Daniel is with her.' },
    team: [['Ruth', 'Sonographer', 'crew']],
    diff: 'Year 3', protocol: 'anomaly',
    objectives: [['Consent and explain the scan in plain words', true], ['Obtain the standard mid-trimester views', true], ['Biometry: HC, AC, FL within range', true], ['Placental site and liquor', true], ['Break uncertain news kindly', false]],
    minutes: 18, items: 26, scheme: [['Consent, explanation', 5], ['Head and brain', 4], ['Face and spine', 3], ['Heart views', 4], ['Abdomen, kidneys', 4], ['Limbs, femur', 2], ['Placenta, liquor', 2], ['Report in notebook', 2]], crowdLabel: 'Partner in the room',
    stressLabel: 'about every 2 min',
    disruptors: [['Partner asks “is that the heart?”', true], ['Sonographer checks your plane', true], ['Patient asks about the sex', false], ['Phone rings in the room', false]],
    face: ['Sarah asks whether the baby is all right while you scan', 'Daniel asks to film the screen', 'Ruth asks you to freeze and measure the head', 'You record HC, AC, FL and your impression'],
  },
}
const PROTOCOLS: [string, string, string][] = [
  ['osce', 'OSCE mark scheme', 'History, examination, plan. Global rating'],
  ['cabcde', '<C>ABCDE + ATMIST', 'Primary survey, haemorrhage first, handover'],
  ['anomaly', 'Mid-trimester anomaly scan', 'Standard views, biometry, placenta'],
]

function Slider({ value, max, ticks, color }: { value: number; max: number; ticks?: number; color?: string }) {
  const pct = (value / max) * 100
  return (
    <div className="sl" style={{ ['--p' as string]: `${pct}%`, ['--c' as string]: color }}>
      <div className="sl-track"><div className="sl-fill" /><div className="sl-knob" /></div>
      {ticks && <div className="sl-ticks">{Array.from({ length: ticks + 1 }, (_, i) => <span key={i}>{Math.round((i * max) / ticks)}</span>)}</div>}
    </div>
  )
}
const Seg = ({ opts, on }: { opts: [string, string][]; on: string }) => (
  <div className="seg">{opts.map(([ic, l]) => <span key={l} className={l === on ? 'on' : ''}>{ic && <I n={ic} s={15} />}{l}</span>)}</div>
)

function Generator() {
  const g = GEN[v]
  const order = (id: string) => g.envs.indexOf(id) + 1
  return (
    <Shell active="generator" crumb="Scenarios / New scenario" title="Scenario generator"
      actions={<><button className="btn ghost"><I n="spark" s={16} />Refine with AI author</button><button className="btn primary"><I n="goggles" s={17} />Play on Vision Pro</button></>}>
      <div className="gen">
        <div className="gen-form">
          <section className="card">
            <div className="card-h"><h3>Environment</h3><span className="hint">{g.envs.length > 1 ? `Journey: ${g.envs.length} places, in order of play` : 'Single place'}</span></div>
            <div className="envs">
              {ENVS.map(e => {
                const n = order(e.id)
                return (
                  <figure key={e.id} className={`env ${n ? 'on' : ''}`}>
                    <div className="env-pic" style={{ backgroundImage: `url(${e.pic})` }}>{n > 0 && <b className="env-n">{g.envs.length > 1 ? n : <I n="check" s={14} />}</b>}</div>
                    <figcaption>{e.name}</figcaption>
                  </figure>
                )
              })}
            </div>
            <div className="env-row">
              <div><span>Time of day</span><Seg on={g.time} opts={[['sun', 'Day'], ['dusk', 'Dusk'], ['moon', 'Night']]} /></div>
              <div><span>Weather</span><Seg on={g.weather} opts={[['sun', 'Clear'], ['cloud', 'Overcast'], ['rain', 'Rain']]} /></div>
              <div><span>Difficulty</span><Seg on={g.diff} opts={[['', 'Year 3'], ['', 'Final-year'], ['', 'FY1']]} /></div>
            </div>
          </section>

          <div className="gen-cols">
            <div className="gen-col">
              <section className="card">
                <div className="card-h"><h3>Crowd</h3><span className="val"><b>{g.crowd}</b> {g.crowd === 1 ? 'bystander' : 'bystanders'}</span></div>
                <Slider value={g.crowd} max={12} ticks={4} color="var(--by)" />
                <div className="crowd">{Array.from({ length: 12 }, (_, i) => <i key={i} className={i < g.crowd ? 'on' : ''} />)}</div>
                <p className="sub">{g.crowdLabel}</p>
              </section>
              <section className="card">
                <div className="card-h"><h3>Distraction</h3><span className="val"><b>{g.stress}</b> per min</span></div>
                <Slider value={g.stress} max={6} ticks={3} color="var(--warn)" />
                <p className="sub">Someone interrupts you {g.stressLabel}</p>
                <ul className="toggles">{g.disruptors.map(([l, on]) => <li key={l} className={on ? 'on' : ''}><span className="tg" />{l}</li>)}</ul>
              </section>
            </div>
            <div className="gen-col">
              <section className="card">
                <div className="card-h"><h3>Patient</h3><span className="hint">Voice and persona</span></div>
                <div className="persona">
                  <span className="av av-pt">{g.persona.init}</span>
                  <div><b>{g.persona.name}, {g.persona.age}</b><p>{g.persona.line}</p></div>
                </div>
                <dl className="facts">
                  <div><dt>Sex</dt><dd>{g.persona.sex}</dd></div>
                  <div><dt>Mood</dt><dd className="pt">{g.persona.mood}</dd></div>
                  <div><dt>Language</dt><dd>{g.persona.lang}</dd></div>
                </dl>
              </section>
              <section className="card">
                <div className="card-h"><h3>Team</h3><span className="hint">{g.team.length} {g.team.length === 1 ? 'person' : 'people'}</span></div>
                <ul className="team">{g.team.map(([n, r, k]) => <li key={n}><span className={`av av-sm av-${k}`}>{n.replace('Dr ', '')[0]}</span><b>{n}</b><small>{r}</small></li>)}</ul>
              </section>
            </div>
            <div className="gen-col">
              <section className="card">
                <div className="card-h"><h3>Learning objectives</h3></div>
                <ul className="objs">{g.objectives.map(([o, on]) => <li key={o} className={on ? 'on' : ''}><span className="cb">{on && <I n="check" s={12} />}</span>{o}</li>)}</ul>
              </section>
              <section className="card">
                <div className="card-h"><h3>Assessment protocol</h3></div>
                <div className="protos">{PROTOCOLS.map(([id, n, d]) => <div key={id} className={`proto ${id === g.protocol ? 'on' : ''}`}><span className="rb" /><div><b>{n}</b>{id === g.protocol && <small>{d}</small>}</div></div>)}</div>
              </section>
            </div>
          </div>
        </div>

        <aside className="preview">
          <div className="pv-cover" style={{ backgroundImage: `url(${g.cover})` }}>
            <span className="pv-live"><i />Live preview</span>
            {g.envs.length > 1 && <ol className="pv-path">{g.envs.map(id => <li key={id}>{ENVS.find(e => e.id === id)!.name}</li>)}</ol>}
          </div>
          <div className="pv-body">
            <h2>{g.title}</h2>
            <p className="pv-line"><span className="av av-xs av-pt">{g.persona.init}</span>{g.persona.name}, {g.persona.age} · {g.persona.mood.toLowerCase()} · {g.time.toLowerCase()}, {g.weather.toLowerCase()}</p>
            <div className="pv-stats">
              <div><I n="clock" /><b>{g.minutes} min</b><small>estimated</small></div>
              <div><I n="users" /><b>{g.crowd + g.team.length}</b><small>people around</small></div>
              <div><I n="bolt" /><b>{g.stress}/min</b><small>interruptions</small></div>
              <div><I n="doc" /><b>{g.items} items</b><small>{PROTOCOLS.find(p => p[0] === g.protocol)![1]}</small></div>
            </div>
            <h4>What the learner will face</h4>
            <ul className="pv-face">{g.face.map(f => <li key={f}>{f}</li>)}</ul>
            <h4 className="pv-h">Scored item by item</h4>
            <ul className="pv-scheme">{g.scheme.map(([l, n]) => <li key={l}><span>{l}</span><i style={{ width: `${n * 5}px` }} /><b>{n}</b></li>)}</ul>
            <div className="pv-foot"><span><I n="shield" s={16} />Clinical check passed</span><span>Ready for Vision Pro</span></div>
          </div>
        </aside>
      </div>
    </Shell>
  )
}

/* Forearm radiograph (AP + lateral): cortex drawn as a light outer stroke over a darker medullary canal. */
const Bone = ({ d, w }: { d: string; w: number }) => <><path d={d} stroke="#e8eff1" strokeWidth={w} fill="none" strokeLinecap="round" /><path d={d} stroke="#7d8b8f" strokeWidth={w * 0.42} fill="none" strokeLinecap="round" /></>
function XrView({ x, lat }: { x: number; lat?: boolean }) {
  const o = lat ? 3 : 0
  return (
    <g transform={`translate(${x} 0)`} filter="url(#xb)">
      <path d="M11 0 Q30 -2 49 0 Q47 50 45 96 L16 96 Q13 50 11 0z" fill="#7d8a8e" opacity=".32" />
      <path d="M24 -2 L36 -2 Q37 6 41 11 Q42 16 37 17 Q33 14 30 16 Q26 14 22 17 Q18 15 19 11 Q23 6 24 -2z" fill="#e3eaec" /><path d="M27 -2 L33 -2 Q33 6 31 10 Q29 6 27 -2z" fill="#8f9da1" />
      <Bone d={`M${25 + o} 19 Q${23 + o} 32 ${24 + o} 46`} w={5.6} />
      <Bone d={`M${28 + o} 49 Q${25 + o} 64 ${24 + o * 0.5} 79`} w={6.4} />
      <Bone d={`M${36 - o} 18 Q${37 - o} 31 ${36 - o} 45`} w={5} />
      <Bone d={`M${39 - o} 47 Q${38 - o} 64 ${35 - o} 79`} w={4.4} />
      <path d={`M${21 + o} 46 l3 2 l3 -2.5 l3 2`} stroke="#0b0f10" strokeWidth="1.1" fill="none" />
      <path d={`M${33 - o} 45 l2.5 2 l3 -2`} stroke="#0b0f10" strokeWidth="1" fill="none" />
      <path d={`M${18 + o} 80 Q${26 + o * 0.5} 77 ${40 - o} 81 L${41 - o} 85 Q29 88 ${17 + o} 84z`} fill="#e6edef" />
      {[0, 1, 2, 3].map(i => <ellipse key={i} cx={21 + i * 6} cy={89} rx={3} ry={2.6} fill="#d5dee1" />)}
      {[0, 1, 2, 3].map(i => <path key={`m${i}`} d={`M${20 + i * 6.5} 92 L${18 + i * 7.5} 100`} stroke="#d5dee1" strokeWidth="3" />)}
    </g>
  )
}
const Xray = () => (
  <svg className="xr" viewBox="0 0 120 96" aria-label="Forearm radiograph, AP and lateral">
    <defs><filter id="xb"><feGaussianBlur stdDeviation=".45" /></filter><radialGradient id="xg" cx="50%" cy="45%" r="75%"><stop offset="0" stopColor="#1d2427" /><stop offset="1" stopColor="#030405" /></radialGradient></defs>
    <rect width="120" height="96" fill="url(#xg)" />
    <XrView x={0} /><XrView x={60} lat />
    <line x1="60" y1="4" x2="60" y2="92" stroke="#000" strokeWidth="1.2" />
    <text x="5" y="10" fill="#f2f5f6" fontSize="7" fontWeight="700" fontFamily="Arial, sans-serif">L</text>
    <text x="4" y="92" fill="#cdd6d9" fontSize="4.6" fontFamily="Arial, sans-serif">AP</text>
    <text x="64" y="92" fill="#cdd6d9" fontSize="4.6" fontFamily="Arial, sans-serif">LAT</text>
  </svg>
)

/* ---------- AI author ---------- */
type Step = { tool: string; label: string; detail: string; state: 'done' | 'run' | 'wait'; ms?: string }
const STEPS_A: Step[] = [
  { tool: 'plan_case', label: 'Planned the case', detail: 'Single place: forest trail. 1 patient, 4 hikers, 2 mountain-rescue volunteers. 25 min.', state: 'done', ms: '2.1 s' },
  { tool: 'draft_history', label: 'Drafted the history', detail: 'Mia, 27. Fell over the handlebars on a descent 20 min ago. Left forearm. No head strike, helmet intact.', state: 'done', ms: '4.8 s' },
  { tool: 'set_exam_findings', label: 'Set examination findings', detail: 'Open wound 3 cm volar mid-forearm, bone visible, oozing. Radial pulse present, CRT 2 s. Sensation intact.', state: 'done', ms: '3.6 s' },
  { tool: 'choose_imaging', label: 'Chose imaging', detail: 'Forearm AP + lateral, wrist and elbow included: displaced midshaft radius and ulna fractures (Gustilo II).', state: 'done', ms: '2.9 s' },
  { tool: 'write_mark_scheme', label: 'Writing the mark scheme', detail: '<C>ABCDE + ATMIST, 30 items. Critical: haemorrhage control, wound cover, neurovascular check before and after splint…', state: 'run' },
  { tool: 'clinical_safety_check', label: 'Clinical safety check', detail: 'Doses, red flags, plausibility against open-fracture guidance', state: 'wait' },
]
const STEPS_B: Step[] = [
  { tool: 'edit_cast', label: 'Changed a hiker into a nurse', detail: 'Karin, off-duty nurse. Questions your splint and asks about antibiotics, about every 3 min.', state: 'done', ms: '2.4 s' },
  { tool: 'add_decision', label: 'Added a decision point', detail: 'Bleeding increases at 06:00 if the wound is not dressed. Tourniquet needed only if pressure fails.', state: 'done', ms: '3.1 s' },
  { tool: 'update_mark_scheme', label: 'Updated the mark scheme', detail: '+3 items: direct pressure first, tourniquet time noted, handles a challenging bystander calmly.', state: 'done', ms: '2.2 s' },
  { tool: 'clinical_safety_check', label: 'Clinical safety check', detail: 'Passed. 1 note: guidance wants antibiotics within 1 h of injury; scored as “asks for early antibiotics” in the handover.', state: 'done', ms: '5.0 s' },
]

function AuthorBody({ b }: { b: boolean }) {
  const steps = !b ? STEPS_A : STEPS_B
  return (
      <div className="au">
        <section className="chat">
          <div className="msg me">
            <span className="av av-sm av-me">EH</span>
            <div><p>Mountain biker with an open forearm fracture on a forest trail, 4 anxious hikers, high distraction, final-year students.</p><small>00:41</small></div>
          </div>
          {b && <>
            <div className="msg ai collapsed"><span className="av av-sm av-ai"><I n="spark" s={14} /></span><div><p>Draft ready: <b>Open forearm fracture on a forest trail</b>. 6 steps, safety check passed.</p></div></div>
            <div className="msg me">
              <span className="av av-sm av-me">EH</span>
              <div><p>Make one hiker an off-duty nurse who second-guesses your splint, and let the bleeding get worse if they don’t dress the wound.</p><small>00:46</small></div>
            </div>
          </>}
          <div className="msg ai">
            <span className="av av-sm av-ai"><I n="spark" s={14} /></span>
            <div className="agent">
              <p>{!b ? 'Building a single-place trail scenario. I’ll base findings on open-fracture guidance and score with <C>ABCDE + ATMIST.' : 'Updating the cast, adding a timed deterioration and re-checking safety.'}</p>
              <ol className="steps">
                {steps.map(s => (
                  <li key={s.tool} className={s.state}>
                    <span className="st">{s.state === 'done' ? <I n="check" s={13} /> : s.state === 'run' ? <i className="spin" /> : null}</span>
                    <div>
                      <div className="st-h"><b>{s.label}</b><code>{s.tool}</code>{s.ms && <small>{s.ms}</small>}</div>
                      <p>{s.detail}</p>
                    </div>
                  </li>
                ))}
              </ol>
            </div>
          </div>
          <div className="composer">
            <span>{!b ? 'Ask for changes, e.g. “make it night and raining”' : 'Ask for another change'}</span>
            <div className="comp-r"><I n="mic" s={18} /><button className="btn primary sm"><I n="send" s={15} /></button></div>
          </div>
        </section>

        <section className="draft">
          <div className="dr-cover" style={{ backgroundImage: `url(${img('webstudio-forest-mossy.jpg')})` }}>
            <div className="dr-cover-t">
              <span className="pill">{!b ? 'Draft · writing' : 'Draft v2 · ready'}</span>
              <h2>Open forearm fracture on a forest trail</h2>
              <p>Mia, 27, mountain biker · forest trail, afternoon, light rain · final-year · 25 min</p>
            </div>
          </div>
          <div className="dr-grid">
            <div className="dr-block">
              <h4>People</h4>
              <ul className="cast">
                <li><span className="av av-sm av-pt">M</span><b>Mia, 27</b><small>Patient · in pain, scared about her arm</small></li>
                <li><span className="av av-sm av-crew">T</span><b>Tom and Ana</b><small>Mountain rescue · arrive at 04:00 with the kit</small></li>
                {b
                  ? <li className="new"><span className="av av-sm av-by">K</span><b>Karin</b><small>Off-duty nurse · questions your splint</small><em>new</em></li>
                  : <li><span className="av av-sm av-by">K</span><b>Karin</b><small>Hiker · keeps asking for a helicopter</small></li>}
                <li><span className="av av-sm av-by">+3</span><b>3 hikers</b><small>Anxious, crowd in, offer water</small></li>
              </ul>
              <h4 className="gap">Stress</h4>
              <div className="stress"><b>High</b><span>4 interruptions / min</span><div className="bar warn"><i style={{ width: '80%' }} /></div><small>Hikers ask for a helicopter, offer water, film on phones. Rain gets heavier after 8 min.</small></div>
            </div>
            <div className="dr-block">
              <h4>History</h4>
              <p>Went over the handlebars on a rooty descent 20 min ago, landed on the outstretched left arm. Right-handed. No head strike, no neck pain, no loss of consciousness. Allergies: none. Last meal 2 h ago.</p>
              <h4>Examination</h4>
              <p>A clear, B RR 20, C HR 104, BP 128/80. 3 cm volar wound mid-forearm, bone visible, steady ooze. Radial pulse present, CRT 2 s, sensation intact in all three nerves.</p>
            </div>
            <div className="dr-block">
              <h4>Imaging</h4>
              <div className="imaging"><Xray /><p><b>Forearm AP + lateral</b>Displaced midshaft radius and ulna</p></div>
              <h4>Mark scheme · &lt;C&gt;ABCDE + ATMIST</h4>
              <table className="ms">
                <tbody>
                  <tr><td>Scene safe, gloves, introduces self</td><td>2</td></tr>
                  <tr className="crit"><td>Direct pressure, sterile dressing on wound</td><td>3</td></tr>
                  <tr className="crit"><td>Neurovascular check before and after splint</td><td>3</td></tr>
                  <tr><td>Analgesia offered, dose appropriate</td><td>2</td></tr>
                  {b && <tr className="new"><td>Handles nurse’s challenge calmly, explains plan</td><td>2</td></tr>}
                  <tr className={!b ? 'writing' : ''}><td>ATMIST handover to rescue team</td><td>{!b ? '…' : '3'}</td></tr>
                </tbody>
              </table>
              <small className="ms-more">{!b ? '18 of 30 items written' : '33 items · 6 critical · pass 70%'}</small>
            </div>
          </div>
          <div className={`safety ${!b ? 'pending' : ''}`}>
            <I n="shield" s={20} />
            <div><b>{!b ? 'Clinical safety check runs when the mark scheme is complete' : 'Clinical safety check passed'}</b>
              <small>{!b ? 'Checks doses, red flags and findings against current open-fracture guidance' : 'Doses within BNF ranges · findings consistent · 1 note added for reviewers'}</small></div>
            {b && <button className="btn primary sm">Send for clinician review</button>}
          </div>
        </section>
      </div>
  )
}

function Author() {
  return (
    <Shell active="author" crumb="Scenarios / AI author" title="AI scenario author"
      actions={<><button className="btn ghost"><I n="mix" s={16} />Open in generator</button><button className="btn primary"><I n="globe" s={16} />Publish</button></>}>
      <AuthorBody b={v === 'b'} />
    </Shell>
  )
}

/* ---------- publish ---------- */
function Publish() {
  const done = v === 'b'
  return (
    <Shell active="author" crumb="Scenarios / AI author" title="AI scenario author">
      <div className="dimmed" aria-hidden><AuthorBody b /></div>
      <div className="scrim">
        {!done ? (
          <div className="dialog">
            <div className="dlg-h"><h2>Publish to Marketplace</h2><I n="x" s={20} /></div>
            <div className="dlg-grid">
              <div className="dlg-form">
                <label className="f"><span>Title</span><div className="in">Open forearm fracture on a forest trail</div></label>
                <label className="f"><span>Summary</span><div className="in ta">A mountain biker has an open forearm fracture far from the road. Control bleeding, splint, manage four anxious hikers and a nurse who questions you, then hand over to mountain rescue.</div></label>
                <div className="f"><span>Tags</span><div className="tags">{['Trauma', 'Pre-hospital', 'Open fracture', 'Crowd management', 'Final-year'].map(t => <i key={t}>{t}<I n="x" s={11} /></i>)}<i className="add"><I n="plus" s={12} />Add</i></div></div>
                <div className="f2">
                  <div className="f"><span>Licence</span>
                    <div className="lic">
                      <div className="on"><span className="rb" /><b>CC BY 4.0</b><small>Others may adapt with credit</small></div>
                      <div><span className="rb" /><b>CC BY-NC-SA</b><small>Non-commercial, share alike</small></div>
                      <div><span className="rb" /><b>Institution only</b><small>Northgate staff</small></div>
                    </div>
                  </div>
                  <div className="f"><span>Version</span><div className="in mono">1.0.0</div>
                    <span className="sp">What changed</span><div className="in ta sm">First release. Nurse bystander, timed bleeding, 33-item mark scheme.</div></div>
                </div>
              </div>
              <div className="dlg-side">
                <div className="review">
                  <div className="rv-h"><I n="shield" s={20} /><div><b>Clinician-reviewed</b><small>Dr Amara Okafor, consultant in emergency medicine · 13 Nov 2026</small></div></div>
                  <ul>{['History and findings plausible', 'Imaging matches the injury', 'Mark scheme weights agreed', 'Analgesia doses checked', 'AI safety check passed'].map(t => <li key={t}><I n="check" s={14} />{t}</li>)}</ul>
                </div>
                <div className="mini-card">
                  <div className="mc-cover" style={{ backgroundImage: `url(${img('webstudio-forest-mossy.jpg')})` }}><span className="badge-proto">&lt;C&gt;ABCDE + ATMIST</span></div>
                  <div className="mc-b"><b>Open forearm fracture on a forest trail</b><small>Northgate Medical School · v1.0.0</small></div>
                </div>
                <p className="fine">How it appears in the Marketplace</p>
              </div>
            </div>
            <div className="dlg-f">
              <span className="vis"><I n="globe" s={16} />Visible to all institutions</span>
              <div><button className="btn ghost">Save draft</button><button className="btn primary big"><I n="globe" s={17} />Publish to Marketplace</button></div>
            </div>
          </div>
        ) : (
          <div className="dialog done">
            <div className="ok-ring"><I n="check" s={40} /></div>
            <h2>Published to Marketplace</h2>
            <p className="lead">Open forearm fracture on a forest trail · v1.0.0 · CC BY 4.0</p>
            <div className="code-row">
              <div><small>Launch code on Vision Pro</small><b className="mono">TRAIL-7K4Q</b></div>
              <div><small>Status</small><b className="ok-t"><I n="shield" s={16} />Clinician-reviewed</b></div>
              <div><small>First hour</small><b>38 downloads</b></div>
            </div>
            <div className="mini-card wide">
              <div className="mc-cover" style={{ backgroundImage: `url(${img('webstudio-forest-mossy.jpg')})` }}><span className="badge-proto">&lt;C&gt;ABCDE + ATMIST</span></div>
              <div className="mc-b"><b>Open forearm fracture on a forest trail</b><small>Northgate Medical School · Trauma · Pre-hospital · 25 min</small></div>
            </div>
            <div className="dlg-f c"><button className="btn ghost">View in Marketplace</button><button className="btn primary big"><I n="goggles" s={18} />Send to Vision Pro</button></div>
          </div>
        )}
      </div>
    </Shell>
  )
}

/* ---------- marketplace ---------- */
type Item = { t: string; inst: string; cover: string; proto: string; rating: number; n: number; dl: string; mins: number; kind: string; reviewed: boolean; tags: string }
const ITEMS: Item[] = [
  { t: 'Wrist injury after a bicycle fall', inst: 'Northgate Medical School', cover: img('webstudio-cover-wrist-pain.jpg'), proto: 'OSCE mark scheme', rating: 4.8, n: 212, dl: '3.4k', mins: 15, kind: 'Clinic', reviewed: true, tags: 'History · Exam · X-ray' },
  { t: 'Mid-pregnancy scan, 20 weeks', inst: 'St Brigid’s Simulation Centre', cover: img('webstudio-cover-us-card.jpg'), proto: 'Anomaly-scan checklist', rating: 4.9, n: 168, dl: '2.1k', mins: 18, kind: 'Antenatal', reviewed: true, tags: 'Ultrasound · Consent' },
  { t: 'Open forearm fracture on a forest trail', inst: 'Northgate Medical School', cover: img('webstudio-forest-mossy.jpg'), proto: '<C>ABCDE + ATMIST', rating: 4.7, n: 41, dl: '612', mins: 25, kind: 'Wilderness', reviewed: true, tags: 'Pre-hospital · Crowd' },
  { t: 'Older adult fall at home, daughter on the phone', inst: 'Lakeside University Hospital', cover: img('webstudio-home.jpg'), proto: 'OSCE mark scheme', rating: 4.6, n: 97, dl: '1.3k', mins: 20, kind: 'Home visit', reviewed: true, tags: 'Frailty · Family' },
  { t: 'Splint fitting in the orthotics lab', inst: 'Harbourview College of Allied Health', cover: img('webstudio-cover-wrist-splint.jpg'), proto: 'OSCE mark scheme', rating: 4.5, n: 63, dl: '840', mins: 12, kind: 'Clinic', reviewed: false, tags: 'Procedure · Orthotics' },
  { t: 'Cyclist down: splint and ATMIST pre-alert', inst: 'Lakeside University Hospital', cover: img('webstudio-cover-rt-splint.jpg'), proto: '<C>ABCDE + ATMIST', rating: 4.8, n: 134, dl: '1.9k', mins: 22, kind: 'Pre-hospital', reviewed: true, tags: 'Teamwork · Handover' },
]

function Stars({ r }: { r: number }) {
  return <span className="stars">{[0, 1, 2, 3, 4].map(i => <I key={i} n="star" s={13} cls={i < Math.round(r) ? 'f' : ''} />)}<b>{r.toFixed(1)}</b></span>
}
function MarketCard({ it }: { it: Item }) {
  return (
    <article className="mk">
      <div className="mk-cover" style={{ backgroundImage: `url(${it.cover})` }}>
        <span className="badge-proto">{it.proto}</span>
        <span className="mk-kind">{it.kind} · {it.mins} min</span>
      </div>
      <div className="mk-b">
        <h3>{it.t}</h3>
        <p className="inst">{it.inst}{it.reviewed && <span className="rev"><I n="shield" s={13} />Clinician-reviewed</span>}</p>
        <div className="mk-meta"><Stars r={it.rating} /><small>({it.n})</small><span className="dl"><I n="down" s={14} />{it.dl}</span></div>
        <div className="mk-f"><small>{it.tags}</small><button className="btn soft sm"><I n="goggles" s={15} />Send to Vision Pro</button></div>
      </div>
    </article>
  )
}

function Marketplace() {
  return (
    <Shell active="marketplace" crumb="Community" title="Scenario marketplace"
      actions={<button className="btn primary"><I n="globe" s={16} />Publish a scenario</button>}>
      {v === 'a' ? (
        <div className="mkt">
          <div className="feat">
            <div className="feat-pic" style={{ backgroundImage: `url(${img('webstudio-cover-rt-crew.jpg')})` }} />
            <div className="feat-t">
              <span className="pill">Featured journey · 3 places</span>
              <h2>Cyclist versus car: roadside to resus</h2>
              <p>Treat Jordan with paramedic Sam at a busy junction, reassess him in the ambulance, then hand over to the trauma team. Six bystanders, sirens and a man filming you.</p>
              <div className="feat-m"><Stars r={4.9} /><small>(486)</small><span className="dl"><I n="down" s={15} />7.8k</span><span className="badge-proto solid">&lt;C&gt;ABCDE + ATMIST</span><span className="rev l"><I n="shield" s={14} />Clinician-reviewed</span></div>
              <div className="feat-a"><button className="btn primary big"><I n="goggles" s={18} />Send to Vision Pro</button><button className="btn glass">Preview</button></div>
            </div>
          </div>
          <div className="filters">
            {['All', 'OSCE mark scheme', '<C>ABCDE + ATMIST', 'Anomaly-scan checklist', 'Clinician-reviewed', 'Journeys', 'Under 20 min'].map((f, i) => <span key={f} className={i === 0 ? 'on' : ''}>{f}</span>)}
            <span className="sort">Most downloaded this month</span>
          </div>
          <div className="mk-grid">{ITEMS.slice(0, 6).map(it => <MarketCard key={it.t} it={it} />)}</div>
        </div>
      ) : (
        <div className="detail">
          <div className="dt-main">
            <div className="dt-media">
              <div className="dt-hero" style={{ backgroundImage: `url(${img('webstudio-cover-us-hero.jpg')})` }}>
                <span className="badge-proto solid">Anomaly-scan checklist</span>
              </div>
              <div className="dt-thumbs">{['us-probe', 'us-monitor', 'us-checklist'].map(s => <div key={s} style={{ backgroundImage: `url(${img(`webstudio-cover-${s}.jpg`)})` }} />)}</div>
              <div className="dt-reviews">
                <blockquote>“Students finally practise talking while they scan. The partner’s questions are exactly what happens in clinic.”<cite>Midwifery lecturer, Lakeside University</cite></blockquote>
                <blockquote>“The checklist debrief maps straight onto our sonography logbook.”<cite>Ultrasound tutor, Harbourview College</cite></blockquote>
              </div>
            </div>
            <div className="dt-text">
              <h2>Mid-pregnancy scan, 20 weeks</h2>
              <p className="inst">St Brigid’s Simulation Centre · v2.3 · CC BY 4.0 <span className="rev"><I n="shield" s={13} />Clinician-reviewed by Ms Hannah Lindqvist, consultant sonographer</span></p>
              <p>Sarah, 31, is nervous at her first-pregnancy anomaly scan. Get consent, scan the standard views, measure head, abdomen and femur, and explain what you see in plain words while her partner asks questions.</p>
              <h4>Scored against the mid-trimester checklist</h4>
              <ul className="chk">{['Consent and identity check', 'Head: HC, BPD, ventricles, cerebellum', 'Face: lips; spine in two planes', 'Heart: 4-chamber view and outflow tracts', 'Abdomen: AC, stomach, kidneys, cord insertion', 'Femur length and all four limbs', 'Placental site and liquor volume', 'Explains findings in plain words'].map(t => <li key={t}><I n="check" s={13} />{t}</li>)}</ul>
            </div>
          </div>
          <aside className="send">
            <div className="send-h"><Stars r={4.9} /><small>168 ratings · 2.1k downloads</small></div>
            <h3>Send to Vision Pro</h3>
            <p className="sub">Choose the headsets for Tuesday’s antenatal teaching block.</p>
            <ul className="devs">
              <li className="on"><span className="cb"><I n="check" s={12} /></span><I n="goggles" s={22} /><div><b>Sim Lab 2 · Bay A</b><small>Free · installs in about 1 min</small></div><span className="ready">Ready</span></li>
              <li className="on"><span className="cb"><I n="check" s={12} /></span><I n="goggles" s={22} /><div><b>Sim Lab 2 · Bay B</b><small>In session · Jordan · installs after this run</small></div><span className="queued">Queued</span></li>
              <li><span className="cb" /><I n="goggles" s={22} /><div><b>Skills Hub · 3</b><small>Charging 64% · sends when on Wi-Fi</small></div></li>
            </ul>
            <div className="send-meta">
              <div><small>Size</small><b>184 MB</b></div>
              <div><small>Length</small><b>18 min</b></div>
              <div><small>Launch code</small><b className="mono">SCAN-20W3</b></div>
            </div>
            <div className="assign">
              <h4>Assign to</h4>
              <div className="as-row"><I n="users" s={18} /><div><b>Year 3 · antenatal group B</b><small>12 students · Tue 17 Nov, 09:00–12:00</small></div></div>
              <div className="as-row"><I n="chart" s={18} /><div><b>Scores return to Debriefs</b><small>Checklist results per student, item by item</small></div></div>
            </div>
            <button className="btn primary big full"><I n="goggles" s={18} />Send to 2 headsets</button>
            <p className="fine">Students open MedSim XR, pick the case and play. Results return to your Debriefs.</p>
          </aside>
        </div>
      )}
    </Shell>
  )
}

export default function PitchStudio() {
  return page === 'author' ? <Author /> : page === 'publish' ? <Publish /> : page === 'marketplace' ? <Marketplace /> : <Generator />
}
