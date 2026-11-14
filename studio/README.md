# MedSim Studio

Instructor web interface for MedSim XR: author scenarios, manage the library, direct a live
session, read the debrief. React 18 + TypeScript + Vite; no other runtime dependencies.
The HTTP/WebSocket contract is in [`docs/studio-api.md`](../docs/studio-api.md).

```bash
npm install
npm run dev      # http://localhost:5173, proxies the API to the backend
npm run build    # type-check + production build into dist/
```

`MEDSIM_BACKEND` sets the dev-proxy target (default `http://localhost:8000`):

```bash
MEDSIM_BACKEND=http://localhost:8021 npm run dev
```

The backend serves `dist/` itself at `/app/` (same origin) when it exists, so build once and open
`http://<backend>/app/`. API paths are root-absolute (`/studio/...`); asset paths are relative.

## Pitch screens

`?pitch=1&page=generator|author|publish|marketplace&v=a|b` renders backend-free showcase screens
(`src/pitch/`, lazy-loaded; the normal app is unchanged). `node scripts/pitch_shots.mjs [name]`
refreshes the cover images from `docs/screenshots/pitch` and writes
`docs/screenshots/pitch/studio-web-*.jpg` at 2880x1800 (needs `npm install`, Playwright, python3 + Pillow).
