# Pitch assets: imaging UI (key `uiimaging`)

Loaded only in the pitch run (`-pitch`, `SmokeLog.pitch`). Files in `visionos/MedSimXR/Resources/Pitch/`.
All are illustrative example images from other people, not the simulated patient, and the viewer says so.

| File | Source | Author | Licence | Changes |
|---|---|---|---|---|
| `uiimaging_xray_forearm_ap.jpg`, `uiimaging_xray_forearm_lat.jpg` | https://commons.wikimedia.org/wiki/File:Unterarmschaftfraktur_durch_direktes_Trauma_22M_-_CR_2_Ebenen_-_001.jpg | Hellerhoff | CC BY-SA 4.0 (https://creativecommons.org/licenses/by-sa/4.0/) | Split into its AP and lateral views, each mirrored horizontally (the original is a left forearm, the simulated injury is on the right), greyscale. The derived files are under the same licence. |
| `uiimaging_xray_wrist_lat.jpg` | https://commons.wikimedia.org/wiki/File:X-ray_of_normal_wrist_by_lateral_projection_(crop).jpg | Mikael Häggström, M.D. | CC0 1.0 | Mirrored horizontally, like the bundled PA view of the same series (`Resources/Radiology/wrist_xray_pa.jpg`), greyscale |

The forearm study shows displaced fractures of both forearm bones (direct trauma, 22-year-old man), a close
stand-in for the road trauma case's "displaced fractures of the radius and ulna". The viewer's credit line
names the author and licence.
