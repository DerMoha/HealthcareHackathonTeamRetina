# MedSim Studio

The instructor web interface for MedSim XR. Author scenarios, manage the library, direct live sessions, and review debriefs. The frontend uses React, TypeScript, and Vite.

## Build and serve

With Node.js and npm installed, run these commands from `studio/`.

```bash
npm ci
npm run build
```

Start or restart the [backend](../backend/README.md), then open <http://localhost:8000/app/>. The backend mounts `studio/dist/` when it starts. The build includes the TypeScript check.

## Develop locally

With the backend running, use `npm run dev` and open <http://localhost:5173/>. Vite proxies requests to `http://localhost:8000` by default. For a backend on a different port, run `MEDSIM_BACKEND=http://localhost:8021 npm run dev`.

See the [Studio walkthrough](../docs/medsim-studio.md) and the [HTTP and WebSocket contract](../docs/studio-api.md).

## Pitch screens

The query string `?pitch=1&page=generator|author|publish|marketplace&v=a|b` selects a backend-free showcase screen. Use one value for each option. The [screenshot guide](../docs/screenshots/pitch/README.md#re-shooting-one-scene) explains how to regenerate the images.
