# Obstetric ultrasound example images

Bundled in the app from `visionos/MedSimXR/Resources/Ultrasound/`. The machine-readable list (view, title, caption, gestational age, source, licence, changes) is `ultrasound_manifest.json` in that folder.

**The images come from different pregnancies.** They are illustrative stand-ins for a simulated case (a healthy singleton at about 20 to 22 weeks), not scans of one patient. Several show measurement values that belong to their own source fetus (listed below), so the simulated case facts should not contradict them.

`gestational_age_weeks` in the manifest is decimal weeks (20+5 is 20.7). Licences were read from the Wikimedia Commons file metadata and from the PubMed Central article licence statement on 2026-11-13.

| File | View | GA (weeks) | Source | Author | Licence | Changes |
|---|---|---|---|---|---|---|
| `us_overview.jpg` | overview | 20+5 | https://commons.wikimedia.org/wiki/File:Obstetric_ultrasound_scan_monitor_showing_20-week_human_fetus_profile_in_Navi_Mumbai_2015.jpg | Goleisureintl | CC BY 4.0 | Photo of a monitor, cropped to the sonogram sector (on-screen case number removed) |
| `us_head_bpd.jpg` | head_bpd | 20+0 | https://pmc.ncbi.nlm.nih.gov/articles/PMC12767545/ (Fig. 3) | Verma AK, Singh A, Lal P, Gupta R, Gambhir PS, Gupta N, Dwivedi D, Anand D., Cureus 2025;17(12):e98575 | CC BY 4.0 | JPEG conversion only. Authors' annotations kept. BPD 4.61 cm |
| `us_head_bpd_2.jpg` | head_bpd | 19+3 | same article (Fig. 4) | same | CC BY 4.0 | JPEG conversion only. HC 16.73 cm, OFD 5.78 cm |
| `us_head_cerebellum.jpg` | head_cerebellum (extra view) | 19+2 | https://commons.wikimedia.org/wiki/File:Cervelletto_e_cisterna_magna_ecografia_ad_ultrasuoni_Dr._Wolfgang_Moroder.jpg | Wolfgang Moroder | CC BY-SA 3.0 | Cropped: header strip with exam identifier and date, and status bar removed. Cerebellum 2.01 cm, cisterna magna 6.55 mm |
| `us_heart_4ch.jpg` | heart_4ch | not recorded | https://commons.wikimedia.org/wiki/File:Ultrasound_Scan_ND_093.jpg | Nevit Dilmen | CC BY-SA 3.0 | Scan of a print, cropped to the sonogram (clinic name, date, ID field removed) |
| `us_spine.jpg` | spine | 20+1 | https://commons.wikimedia.org/wiki/File:Scan20semanas1.png | Guimi | CC BY-SA 2.5 | PNG to JPEG only |
| `us_spine_2.jpg` | spine | not recorded (probably later than 24) | https://commons.wikimedia.org/wiki/File:Ultrasound_Scan_ND_318.jpg | Nevit Dilmen | CC BY-SA 3.0 | Scan of a print, cropped to the sonogram |
| `us_abdomen_ac.jpg` | abdomen_ac | 19+2 | https://pmc.ncbi.nlm.nih.gov/articles/PMC12767545/ (Fig. 5) | Verma et al. (see above) | CC BY 4.0 | JPEG conversion only. AC 13.82 cm, EFW (Hadlock) 289.04 g |
| `us_femur.jpg` | femur | 19+6 | same article (Fig. 1) | Verma et al. | CC BY 4.0 | JPEG conversion only. FL 3.17 cm |
| `us_profile.jpg` | profile | not stated (study range 16 to 24) | same article (Fig. 2) | Verma et al. | CC BY 4.0 | JPEG conversion only. Nasal bone 0.51 cm |
| `us_placenta.jpg` | placenta | 20+4 | https://commons.wikimedia.org/wiki/File:Human_placenta_umbilical_cord_Ultrasound_by_Dr._W._Moroder.jpg | Wolfgang Moroder | CC BY-SA 3.0 | Cropped: header (patient birth date, time, watermark) and settings column removed |
| `us_umbilical_cord.jpg` | umbilical_cord | 20+4 | same file as above | Wolfgang Moroder | CC BY-SA 3.0 | Tighter crop of the same image |
| `us_amniotic_fluid.jpg` | amniotic_fluid | 20+4 | same file as above | Wolfgang Moroder | CC BY-SA 3.0 | Upper-part crop of the same image |

CC BY-SA images (Dilmen, Guimi, Moroder) require attribution and that derivatives stay under the same licence. CC BY 4.0 images require attribution only.

## Case facts to keep consistent

- Placenta: posterior (on the wall away from the probe), central cord insertion, three-vessel cord, plenty of fluid.
- Cureus figures (`us_head_bpd`, `us_head_bpd_2`, `us_abdomen_ac`, `us_femur`) are from one study at 19 to 20 weeks with the authors' arrows and labels drawn on. Values: BPD 4.61 cm, HC 16.73 cm, AC 13.82 cm, FL 3.17 cm. These suit a 19 to 20 week fetus, slightly less than 22 weeks.
- The Cureus images are about 750 px wide and have an amber tint from the original figure; the Dilmen ones are scans of prints.

## Not found

- `heartbeat_mmode`: the only freely licensed M-mode images found (Nevit Dilmen) show heart rates of 63 and 100 beats/min, which would misrepresent a normal fetus, so none is bundled.
- `femur` from the Dilmen set was dropped as ambiguous. The Cureus femur is used.
