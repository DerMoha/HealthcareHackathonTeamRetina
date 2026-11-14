import { createRoot } from 'react-dom/client'
import App from './App'
import './styles.css'

const root = createRoot(document.getElementById('root')!)
// ?pitch=1: backend-free showcase screens for pitch screenshots (studio/scripts/pitch_shots.mjs).
if (new URLSearchParams(location.search).has('pitch')) void import('./pitch/PitchStudio').then(m => root.render(<m.default />))
else root.render(<App />)
