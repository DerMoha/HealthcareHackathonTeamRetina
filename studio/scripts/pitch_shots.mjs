// Pitch screenshots of the Studio web app (?pitch=1, no backend needed).
//   node scripts/pitch_shots.mjs              all scenes
//   node scripts/pitch_shots.mjs marketplace  only scenes whose name contains the argument (e.g. 03, ai-author-b)
// Refreshes the cover images from docs/screenshots/pitch first, starts Vite, writes
// docs/screenshots/pitch/studio-web-0N-<name>[-b].jpg at 2880x1800.
import { spawn, execFileSync } from 'node:child_process'

import { fileURLToPath } from 'node:url'
import { chromium } from 'playwright'

const studio = fileURLToPath(new URL('..', import.meta.url))
const shotsDir = `${studio}../docs/screenshots/pitch/`
const coverDir = `${studio}public/pitch/shots/`
const SCENES = [
  ['studio-web-01-generator', 'generator'], ['studio-web-02-ai-author', 'author'],
  ['studio-web-03-publish', 'publish'], ['studio-web-04-marketplace', 'marketplace'],
].flatMap(([name, page]) => [[name, page, 'a'], [`${name}-b`, page, 'b']])
const only = process.argv[2]
const scenes = SCENES.filter(([n]) => !only || n.includes(only))
if (!scenes.length) throw new Error(`no scene matches "${only}"`)

execFileSync('python3', ['-I', `${studio}scripts/pitch_covers.py`, shotsDir, coverDir], { stdio: 'inherit' })

const port = 5199
const vite = spawn('npx', ['vite', '--port', String(port), '--strictPort'], { cwd: studio, stdio: ['ignore', 'pipe', 'inherit'] })
await new Promise((ok, fail) => { vite.stdout.on('data', d => String(d).includes('Local') && ok()); vite.on('exit', fail) })
const browser = await chromium.launch()
try {
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 })
  const page = await ctx.newPage()
  for (const [name, p, v] of scenes) {
    await page.goto(`http://localhost:${port}/?pitch=1&page=${p}&v=${v}`, { waitUntil: 'networkidle' })
    await page.waitForSelector('.ps')
    await page.evaluate(() => document.fonts.ready)
    const out = `${shotsDir}${name}.jpg`
    await page.screenshot({ path: out, type: 'jpeg', quality: 88 })
    console.log('wrote', out)
  }
} finally { await browser.close(); vite.kill() }
