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
