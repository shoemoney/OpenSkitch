# docs/design: index

Design docs for the OpenSnap visual and cosmetic audit (2026-10-09, final). Start with `roadmap.md` for the plan, then `todo-checklist.md` for the work items. `backlog.json` is the same work in machine-readable form.

Open [audit-overview.html](audit-overview.html) for the self-contained interactive roadmap and evidence gallery: milestone filtering, task details, shortlisting, side-by-side comparisons, and downloads. It embeds ECharts and a selected set of ten evidence images, including placement mocks explicitly labelled as unimplemented. The full evidence set remains below. Viewer text was checked at 728 and 360 CSS px widths with an 18 px minimum; filtering, previews, shortlisting and comparison were exercised in the browser.

## Files

| File | Owner | Model | Purpose |
|---|---|---|---|
| `README.md` | docs child C (round 2) | `claude-haiku-5-5` | This index: files, evidence key, screenshot location, rerun commands, safety proof, coverage gaps, counts. |
| `roadmap.md` | docs child C (round 2) | `claude-haiku-5-5` | Summary, drift, owner decisions, findings, milestones, lane and file ownership, estimates, gates, risks, outward-facing steps, source inconsistencies. |
| `todo-checklist.md` | docs child C (round 2) | `claude-haiku-5-5` | One section per todo (36 todos, OSN-001 to OSN-072 as numbered in `visual-audit.md` section 9), in milestone order: main state, substeps, files, prerequisites, estimates, acceptance, visual checks with BEFORE stems, and tests. |
| `backlog.json` | docs child C (round 2) | `claude-haiku-5-5` | The same backlog as JSON: `meta`, `decisions` (10), `milestones` (8), `todos` (36), `findings` (29). Every todo has `"status": "pending"` and a `mainState`. |
| `visual-audit.md` | orchestrator | `claude-opus-5-5` | Source, read-only here. FINAL audit: summary, drift (section 0), coverage (section 5), findings VF-01 to VF-29 (section 6, with status at `dc1eb26` in 6.0), reconciliation (section 7), owner layout (section 8), backlog (section 9). |
| `technical-spec.md` | source and spec child B | `claude-sonnet-5-5` | Source, read-only here. Decisions Q1 to Q5 (section 0), implementation specs T1 to T15, file ownership map (section O). |
| `source-inventory.md` | source and spec child B | `claude-sonnet-5-5` | Source, read-only here. File and line inventory at `4b2ae0f`. |
| `user-feedback.md` | root (owner) | not applicable | Source, read-only here. The owner's 10:24 CDT layout request and its acceptance checks. |
| `evidence/source-font-sizes.json` | source and spec child B | `claude-sonnet-5-5` | Source, read-only here. Font sizes by file and line. |
| `evidence/2026-10-09/` | evidence child A | `claude-sonnet-5-5` | Captures, metrics, AX dumps, menus, `manifest.json`, `captures.md`, `gaps.md`, `layout-width-budget.*`, `safety.txt`. See below. |

## Evidence classes

| Tag | Meaning |
|---|---|
| **R** observed | Seen in an app-owned rendered capture. The capture stem is cited. |
| **M** measured | Read from view-tree metrics, an AX dump, the layout budget, or a probe. The JSON or probe is cited. |
| **S** source-inferred | Read from code at `4b2ae0f` unless stated. Not seen rendered. |
| **U** unverified | Plausible, but neither rendered nor confirmed in source. Check before work starts. |

Findings show the header's evidence class and confidence in the form `R+S/H`: classes, then confidence (H, M or L). The category used for counts (R/M, S, U) is in `roadmap.md` section 13, item 1.

## Severities

| Severity | Meaning |
|---|---|
| **P0** | Blocks the OpenSnap direction. Breaks a hard owner rule (identity, original assets, data safety, the readable-text floor on a primary surface). Or is a foundation other work depends on. |
| **P1** | A visible quality or accessibility defect on a main surface, or an owner-required change. |
| **P2** | Polish. |

## Screenshots and evidence

- **Location:** `docs/design/evidence/2026-10-09/`. 297 captures and metrics (manifest entries). Each capture is named `<surface>-<slug>-<light|dark>`. Captures suffixed `@dc1eb26` were taken at the current main SHA; captures without a suffix were taken at `b9319c4`.
- **Counts (from `manifest.json`):** 297 entries in total: **205** at `b9319c4`, **84** at `dc1eb26`, and **8** PROTO mocks (`sourceSha` `dc1eb26`, rail-less harness mocks, not product).
- **Index:** `manifest.json` lists every capture with its `sourceSha`. `captures.md` is the human index. `gaps.md` lists what was not captured and why. Also: `layout-width-budget.json` and `.md` (live widths at `dc1eb26`), `metrics/` (view-tree metrics), `ax/` (AX dumps), `menus.json` (menu text), `observations.json`, `environment.json` and `environment@dc1eb26.json`, and `safety.txt`.
- **Environment (M):** macOS 27.2 (build 26B5101f), built-in 2x Retina display, system appearance Dark, accent colour yellow. Every accent in the captures is yellow for that reason.

## Regenerating the evidence

The harness is on branch `audit/visual-harness` @ `6ed6828`. **It is unmerged until OSN-001.** Both scripts below live on that branch (`tools/eye-dump-audit.sh` and `tools/eye-dump-audit-assemble.py`); neither is on `main` yet.

```sh
# from a checkout of audit/visual-harness
sh tools/eye-dump-audit.sh OUT --app APP --sha SHA --suffix @SHA --groups main,more,overlays,welcome,delta,proto,layout,fullscreen --appearances light,dark

# assemble the raw outputs into docs/design/evidence/<date>/ (usage from the script header)
python3 -I tools/eye-dump-audit-assemble.py --out DIR --b93 RAW [RAW...] --delta RAW [RAW...] --layout RAW --observations FILE --sha SHA
```

- `OUT` receives `raw/` (per-capture files), `safety.txt` (real-store hashes before and after) and `run.log`. `APP` is a built `OpenSkitch.app`; `SHA` is recorded as `sourceSha` in every capture; `--suffix @SHA` names the delta set.
- The branch script still has the `welcome` group and the old bundle id `com.shoemoney.skitch-redux`. OSN-001 and OSN-030 change those. Do not run it against the owner's live store: OSN-001 makes the isolated bundle id and throwaway defaults domain the only path.
- Group names accepted by the branch script are `main`, `more`, `overlays`, `welcome`, `fullscreen`, plus `layout`, `proto` and `delta`. Appearance names are `light` and `dark`.

## Safety proof

Hashes from `evidence/2026-10-09/safety.txt`, unchanged from the audit's run. No store contents were read, printed or copied.

```
SkitchRedux files hash (find -type f stat name/size/mtime | shasum)  1a388426cc6e209295d62975a3eadd41897e4a75
com.shoemoney.skitch-redux defaults hash (defaults export | shasum)  56fed48e39b705ec21c42dc36bbc55c93b47e0b7
SkitchRedux files hash  1a388426cc6e209295d62975a3eadd41897e4a75
com.shoemoney.skitch-redux defaults hash  56fed48e39b705ec21c42dc36bbc55c93b47e0b7
```

The file records: `RESULT store unchanged, defaults unchanged.` before and after the final GUI run, with cleanup of throwaway defaults domains and temp directories. No network access, no real uploads, no Keychain reads or writes, no screen capture beyond the app's own windows, and no system settings changed.

## Coverage gaps

Full list in `evidence/2026-10-09/gaps.md` and section 5 of the audit. Summary:

- **Not toggled (forbidden):** Reduce Transparency, Increase Contrast, Reduce Motion, Bold Text, Differentiate Without Color. The code paths are source-only. The injected `DisplayOptions` capture mode (OSN-061) closes this.
- **Not run:** VoiceOver speech (the AX dumps are a structural substitute; OSN-062 records a manual pass).
- **Not captured:** the Photo browser (S22, it reads the real Photos library), the menu windows (S23, text only in `menus.json`), the Wipe confirmation (none exists), native tooltips, the system share picker, real drag-and-drop to Finder, real uploads (the publish states use a stubbed uploader), and the save panel (S10 shows the accessory alone).
- **Environment:** a single 2x display only (no 1x, no multi-display), no live desktop behind the picker and countdown (S13, S14), and no Screen Recording grant (so the Frame-mode scroller question, VF-27, stays U until OSN-014 runs a live capture).
- **Flattened:** alert and status-button PNGs are flattened onto a neutral backdrop (`flattenedOnBackdrop` in the manifest, 24 entries). The S09 popup-open capture at `b9319c4` was dropped.

## Counts

| Measure | Count |
|---|---|
| Findings | 29: P0 6, P1 16, P2 7 |
| Findings by evidence category | R/M 22, S 6, U 1 (rule in `roadmap.md` section 13, item 1) |
| Todos | 36: P0 12, P1 20, P2 4 |
| Todos by milestone | M0 2, M1 5, M2 5, M3 3, M4 6, M5 9, M6 3, M7 3 |
| Todos in Lane A (`Sources/App.swift`, serial) | 22 (19 in the serial order, plus 3 landed) |
| Todos new in round 2 | 3: OSN-014, OSN-057, OSN-058 |
| Owner decisions | 10: Q1 to Q5, D-TEXT, D-HINT, D-T15-1 to D-T15-3. Each has a recommended default. |
| Estimate | 18.0 d numeric across 18 todos, plus 17.5 d of unsplit spec figures, total 35.5 d (`roadmap.md` section 8) |
| Status | 36 of 36 `pending`. Four are landed in source at `dc1eb26` (OSN-020 to OSN-023) and need verification. Section 2a of the roadmap. |

## Validating the files

```sh
python3 -m json.tool docs/design/backlog.json > /dev/null
```

The cross-checks (todo IDs, priorities, milestones, dependencies, Lane A, main state, findings and severities against `visual-audit.md` sections 6 and 9, stems against `manifest.json`, and the counts in this file) were run when these files were generated. The generator and checks are kept outside the repo, in `/tmp/osk-docs`, so no tooling was added to `tools/`.

