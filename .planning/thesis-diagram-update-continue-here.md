---
context: research
task: "Update Chapter 4 of thesis with excalidraw sequence/activity diagrams"
status: in_progress
last_updated: 2026-06-25
---

# Continue here: Chapter 4 excalidraw diagram insertion

Not tracked under any GSD phase — this is ad-hoc work on the thesis document
(`C:\Users\navve\Downloads\Corrected PSM Thesis - NavveenNairManoharan - REBUILT.docx`),
unrelated to the `fix/critical-security-and-debt` branch's app-code changes that the
existing `.planning/.continue-here.md` tracks. Do not touch that file for this task.

## Critical anti-pattern — read before re-rendering anything

- `crop_diagrams2.py` (gap-detection-based cropper) is BROKEN — produced garbage crops
  (e.g. SD001 came out 1723x71px). Do not reuse or extend it. The working approach is
  `crop_diagrams.py` (rough grid window from JSON title coordinates + local tight-content
  trim), followed by **manual spot-fixes** for any crop that bleeds into a neighbor —
  verify every crop visually with Read before trusting it.

## Current state

**Task**: User asked to update Chapter 4 with the excalidraw-rendered sequence diagrams
(SD001-SD015) and activity diagrams (AD001-AD015), replacing/completing what's in the
appendices today. User decisions already made (do not re-ask):
- Diagrams go **directly into Chapter 4 body** (not the appendix) — under each existing
  4.3.3.x (SD) / 4.3.4.x (AD) heading.
- Add the 5 missing AD subsections (AD002/003/004/006/009) to Chapter 4's outline now
  that complete diagrams exist for them — brief descriptive text + image each.
- After insertion, must re-run the figure-renumbering pipeline (see below) and rebuild
  the TOC, since this inserts ~30 new chapter-4-bucket figures.

**Source files** (read-only, do not modify):
- `.claude/skills/excalidraw-diagram/references/cryptransfer_sequence_diagrams_v2.excalidraw`
  — SD001-SD015, 3-column grid, canvas bbox `(0,-90,4099.6,3654)`, column x-starts
  `[0,1445,2890]`, row y-starts `[0,762,1412,2230,2992]`.
- `.claude/skills/excalidraw-diagram/references/cryptransfer_activity_diagrams_v2.excalidraw`
  — AD001-AD015, 3-column grid, canvas bbox `(0,-90,4099.225...,7446)`, column x-starts
  `[0,1220,2440]`, row y-starts `[0,1522,2896,4418,6182]`.
- Render via `.claude/skills/excalidraw-diagram/references/.venv/Scripts/python.exe`
  (has playwright+chromium preinstalled).

**Scratchpad** (session-specific temp dir, may not survive to next session — verify
before assuming these still exist):
`C:\Users\navve\AppData\Local\Temp\claude\C--Users-navve-projects-cryptransfer\519e143e-6d32-4d27-bf9b-3890e5450f32\scratchpad\`
- `render_full.py` — working screenshot script (file-chooser load + Shift+1 zoom-to-fit
  + screenshot at 2x device scale). Usage:
  `python render_full.py <excalidraw_path> <out_png> <viewport_w> <viewport_h>`.
  Used `1820x1664` viewport for sequence (matches its ~1.095 aspect ratio) — use
  similar aspect-matched viewport for activity (bbox is taller: 4099x7536, ratio
  ~0.544, so use something like `1820x3346` or split into two renders if that's too
  tall for one viewport).
- `seq_full.png` — full-grid screenshot of sequence diagrams (3640x3328px), already
  rendered and calibrated.
- `crop_diagrams.py` — the working (rough-window) cropper. Usage:
  `python crop_diagrams.py <full_png> <excalidraw_json> <SD|AD prefix> <out_dir> <ncols>`
- `sd_crops/SD001.png` through `SD015.png` — **all 15 done and visually verified
  clean**: SD001 (fixed, had umbrella-title bleed), SD002 (fixed, had UI tooltip
  bleed), SD003-SD011 clean, SD012 (fixed, had bleed from SD011+SD015), SD013-SD015
  clean.

## Completed work

1. Investigated excalidraw source files, confirmed both have complete, codebase-accurate
   15-diagram sets (no gaps, unlike what's currently in the document's Appendix C/D).
2. Asked user 2 clarifying questions (placement, AD-gap fix) — both answered, see above.
3. Rendered `seq_full.png`, calibrated canvas→pixel mapping via content-bbox detection
   (excluding known UI chrome bands: `mask[0:160,:]=False`, `mask[3200:,3400:]=False`).
4. Cropped and verified all 15 sequence diagrams into `sd_crops/`.

## Remaining work

1. **Render activity diagrams**: same process as sequence — `render_full.py` on
   `cryptransfer_activity_diagrams_v2.excalidraw` with an aspect-matched viewport
   (taller grid, may need to split or use a very tall viewport), then `crop_diagrams.py`
   with prefix `AD`, then visually verify all 15 and manually fix any bleed (expect
   2-4 will need touch-ups, same as the sequence batch did).
2. **Insert into Chapter 4 body** in the REBUILT docx:
   - Current state of Chapter 4's 4.3.3.x (SD) and 4.3.4.x (AD) headings: already
     restyled to proper Heading 3/4 (fixed in a prior turn — see git-less change
     history in this conversation, not committed anywhere since the docx is the
     only artifact). 4.3.4.x currently only has AD001, AD005, AD007, AD008, AD010,
     AD011 — need to ADD AD002, AD003, AD004, AD006, AD009 as new 4.3.4.x headings
     with brief text, in correct numeric position (renumber 4.3.4.x sequence to be
     1-15 in AD001-AD015 order).
   - Under each 4.3.3.x heading, insert the corresponding SD crop as an inline image
     with a `Figure 4.X` caption (using `Run.add_picture()` — safe, avoids the
     run.text-clobbers-drawing bug hit earlier this session). Same for 4.3.4.x / AD.
3. **Re-run figure renumbering**: the existing pipeline (anchor-detection by
   media-adjacency + per-bucket sequential renumber, built earlier this session)
   needs to run again over the whole document since ~30 new chapter-4-bucket
   figures are being added physically earlier in the document than the existing
   Appendix C/D figures — full renumber required, not just appending new numbers.
4. **Rebuild TOC** (clear table rows beyond header, rescan Heading 1-4 + REFERENCES/
   Appendix markers, repopulate) — same process used multiple times already this
   session.
5. **Full verification**: zip/XML integrity, image-relationship integrity (no
   broken blips), no duplicate/gapped figure numbers anywhere in the document —
   same checks already proven out this session.

## Decisions made

- Diagrams go in Chapter 4 body, not the appendix (user's explicit choice).
- Add the 5 missing AD subsections rather than leaving Chapter 4's outline
  incomplete (user's explicit choice).
- Appendix C/D's existing (old/stale) diagram images are left untouched — user
  did not ask to replace those, only to update Chapter 4.

## Blockers

None technical — purely a context-budget pause. No human action required to
resume; everything needed is either in the scratchpad (may need re-rendering if
expired) or reconstructable from the excalidraw source files using the documented
calibration approach above.

## Next action when resuming

1. Check if `seq_full.png` and `sd_crops/*.png` still exist in the scratchpad path
   above. If gone (new session = new scratchpad), re-render and re-crop the
   sequence diagrams first (fast — process is now proven, ~10 min of tool calls).
2. Render + crop the 15 activity diagrams (not yet started).
3. Proceed to document insertion (step 2 in Remaining Work above).
