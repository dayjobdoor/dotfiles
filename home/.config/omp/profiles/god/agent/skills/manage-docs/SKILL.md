---
name: manage-docs
description: >-
  Bootstrap, Sync, and Add-topic for project documentation without fabricating facts.
  docs/ holds INTENT (specs, design, rationale); code / CI / manifests hold RUNTIME FACTS
  (commands, defaults, dependencies); the root README and CONTRIBUTING are the ENTRY POINT.
  Agent-only: AGENTS.md (exploration), REVIEW.md (review guidance).
  Use for: /manage-docs, /make-docs, /update-docs, write docs, spec, init docs,
  generate AGENTS.md / REVIEW.md, docs drift, stale README, Sync Full after a release,
  Sync Post-ship after a named change, Add-topic (DESIGN / operations / product / pattern / review),
  Reorganize (merge / dedup / rename / move / split existing docs on request).
  Do not use for: tutorials, changelog authorship, or pure prose rewrites.
---

# /manage-docs

## Quick route

Route with the Router table below (first match; Mix table for ties). Ambiguous → one question, else **blocked**.

## Read this first (canonical)

Before writing: intent or runtime? which file owns it? evidence this session?
Uncertain → omit. Empty or wrong files become the next session's source.

Normal path loads none of `references/`. Load one only when its row in the table below matches exactly; **Do NOT Load** for routing, truth, Bootstrap, ordinary Sync, Verify, Add-topic for product / operations / pattern, or Targeted docs other than `DESIGN.md` / `ROADMAP.md`. Size alone (`docs` > ~6) is not a trigger.

| File | **MANDATORY — READ ENTIRE FILE** | Also **Do NOT Load** |
|---|---|---|
| [`references/background.md`](references/background.md) | user asks *why* this catalog split | Add-topic / DESIGN / ROADMAP structure / split |
| [`references/design.md`](references/design.md) | Add-topic or Targeted is `DESIGN.md` **and** user asked for its structure | whether to create it; catalog why; split |
| [`references/roadmap.md`](references/roadmap.md) | Add-topic or Targeted is `ROADMAP.md` **and** user asked for its structure | whether to create it; catalog why; split |
| [`references/bloat.md`](references/bloat.md) | asked to split; one file unreadably long; docs exceed ~6 **and navigation fails** (Terms); same table in two files | ordinary Bootstrap/Sync/Verify; DESIGN/ROADMAP structure; catalog why |

After a router row wins, **run only that section**: Bootstrap / Sync (Targeted, Full, Post-ship) / Reorganize / Add-topic. Stop is row 1 and Fallback is row 8; neither has a section.

### Terms

- **Runtime source**: commands, defaults, deps, public surface. Code / CI / manifest. docs quote it; docs never become it.
- **Intent source**: what to ship, duties, appearance. `docs/` plus DESIGN / ROADMAP.
- **Unknowns**: no owner and no source. Do not write; list in the report.
- **Gaps**: same axis, two sources disagree (two CIs, two schemas). Write neither; report both.
- **drift**: runtime vs intent disagree on the same fact. Code wins; fix the quote or record in `problems.md`. Do not report as **Gaps** (that freezes a stale quote as a second runtime source).
- **blocked**: cannot pass Verify or cannot read a required path. Report what failed, which side is right, whether a human must choose. Do not continue the route or invent files.
- **navigation fails**: after following the documented reading order (`AGENTS.md` then matching `docs/*`, else README then `docs/`), the reader cannot name one owner, one source, and one entry for the topic, or two files still claim the same axis. Size alone does not count.
- **change set**: what the user named, or the PR / session diff. Absent both, Sync is Full.

### Deciding the source

- Commands: **CI > manifest scripts/targets > source comments**. CI is what actually runs.
- Defaults: **code / schema > README samples** (README mismatch → patch the quote).
- Dependencies: **lockfile / manifest > docs**.
- Silent / no owner → **Unknowns**. Same axis, still two sources → **Gaps**.

### Placement (purpose, not audience)

- **Entry**: `README`, `CONTRIBUTING`. Door only. Runtime quotes only (install, commands, flags, deps, samples); match Facts or report per Terms. Intent does not live here; leaks → move or **drift**.
- **Intent**: `docs/`, DESIGN, ROADMAP.
- **Facts**: code / CI / manifests.
- **Exploration**: `AGENTS.md` only. Short bans and reading order.
- **Review guidance**: `REVIEW.md` only. Scrutiny areas, ignore list, review language; links to `docs/` over restatement.

Humans and agents read every file. "Root = entry + docs/ = intent" is default, not required. Single-layer docs or no AGENTS: keep placement; do not invent a catalog. Cannot decide → stop and ask. Non-interactive: **blocked**, because a guessed layout is coverage.

---

## Router (first match; never mix)

Mixed routes produce create+sync in one pass and leave both trees wrong.

**No `docs/`:** a named file or "add pattern.md" is Bootstrap (row 2), not Sync or Add-topic; row 1 still wins first. Sync cannot invent a tree. Add-topic is a leaf. Exception: a runtime-quote fix (command, flag, dep, install step) to a named existing README / CONTRIBUTING creates nothing, so it stays Sync Targeted (row 4).

| # | Signal | Route |
|---|---|---|
| 1 | Prose only / cosmetic rebuild of existing docs into this catalog | **Stop** |
| 2 | No `docs/` (init / spec-only / missing README / add a row but no tree), unless the ask is only a runtime-quote fix to a named existing README / CONTRIBUTING or a structural change among those two | **Bootstrap** |
| 3 | Named structural change to existing docs (merge / dedup / rename / move / split); `docs/` exists, or the named files are root docs (README / CONTRIBUTING) | **Reorganize** |
| 4 | Named **existing** `README` / `CONTRIBUTING` or one docs path; `docs/` exists, or README / CONTRIBUTING runtime-quote fix with no `docs/` | **Sync Targeted** |
| 5 | One contract row with a reason (UI → DESIGN, quality gate → pattern, review guidance → REVIEW.md, test matrix → testing, threats → security); **`docs/` exists** | **Add-topic** |
| 6 | Reconcile every quote / release or all manifests, with no change set | **Sync Full** |
| 7 | This change, PR, or session shipped; no filename | **Sync Post-ship** |
| 8 | Ambiguous | Fallback |

**Tie-break:** 4 vs 7: named file → Targeted, else Post-ship. Even one `docs/` file is not Bootstrap.

**Full vs Post-ship:** a named change set or "just shipped this" → **Post-ship** (only those rows). "everything" / "release" / "all manifests" / no change set → **Full**. Both phrases and a change set exists → Post-ship.

**Row 8:** Interactive: one question, create from nothing or sync facts? Non-interactive: **blocked**. Read failures and missing links use the State table, not Fallback.

**Example (row 8 boundary):** "docs feel stale," `docs/` exists, no named file, no change set → row 6 (Sync Full), not row 8. Row 8 is only when create-vs-sync is itself undecidable.

**Boundary (row 1 vs 3):** structural verbs ("merge A into B", "rename X to Y") → row 3 even when phrased as catalog alignment; "rewrite for clarity" / "fit this catalog" with no structural verb and no named files → row 1.

| Mix | Route |
|---|---|
| Named file + this change shipped | **Targeted** |
| Release / everything + a named change set | **Post-ship** |
| Named file + a new contract row (README fix + add DESIGN) | `docs/` exists: **Targeted** for the named file, report the row as not done. No `docs/`: **Bootstrap** |
| Prose only + no `docs/` | **Stop** (row 1) |
| `docs` > ~6 and navigation still works | no `bloat.md`; no `guidance.md` |

| State | Do |
|---|---|
| Path unreadable / permission | **blocked** (path + failure). Do not invent files. Interactive: another path or access? Non-interactive: stop. |
| Relative link missing | **blocked**. Interactive: intended target? Else drop the link. |
| External URL | not a source. Pointer OK in `references.md`. Dead link → **Unknowns**, not **Gaps**. Do not fetch as owner. |
| Partial `docs/` (e.g. only requirements) | not Bootstrap; Sync or Add-topic |
| Two entry files (e.g. README.md and README.rst) both claim runtime facts | patch both quotes to the runtime source; no runtime source → **Unknowns** |
| Owner and source disagree | **drift** (Terms): code wins; patch the quote or record in `problems.md` |
| Expected CI missing | this turn needs commands (README already quotes them, or user asked to sync commands) → **blocked**; otherwise omit as **Unknowns**. Do not guess the command. |
| Owner missing | user asked for that file/row → **blocked** (one question if interactive); otherwise **Unknowns** |

---

## Minimal profile (omission is default)

Three files unless a condition below holds.

- `./AGENTS.md` (default layout only; see table below)
- `./docs/requirements.md` (required)
- `./docs/architecture.md` (required)

Add only when:

- ≥2 actors with different failures → `product.md`. One acceptance list hides actor-specific failure.
- UI → `DESIGN.md`. Pixels in architecture mix structure with appearance.
- Operations is how the product is run (on-call, deploy, watch) → `maintenance.md`. Otherwise ops takes over app design.
- Lint/format **gates** beyond the default formatter → `pattern.md` (formatter-only: skip; indent is not a design). Example skip: only `rustfmt` or Prettier, no project-specific rule gate → no `pattern.md`.
- External review agent reviews PRs (Devin Review, CodeRabbit, …) → thin `REVIEW.md`: review-only guidance + links to `docs/`; also let the tool ingest `docs/**` so links resolve. No review agent → skip.
- Rejected technical options exist → `tech.md`. Otherwise the next session reopens the stack.
- Forbidden paths overflow architecture → `directory.md`.
- More than ~6 docs files **and** navigation fails → `guidance.md`. An index "in case" becomes a second spec.

| AGENTS.md | Handling |
|---|---|
| Default layout | Required; content per "Write into AGENTS.md" |
| Already exists | Do not overwrite. Ask only before appending update rules |
| Single-layer / no-AGENTS policy | Do not force. One question: where is the agreed reading order? |

---

## File contract (creation = Minimal profile)

| File | Role | Does not |
|---|---|---|
| `./AGENTS.md` | Short bans, reading order, update rules | Long spec / quality prose (second `docs/`) |
| `./REVIEW.md` | Review-agent guidance: scrutiny areas, ignore list, review language | Restating `security.md` / `problems.md` / `pattern.md` — link instead |
| `./docs/requirements.md` | What ships / does not, how done looks | How it works, schedules |
| `./docs/architecture.md` | Duties, data flow, schemas (intent) | Tech picks, path names, appearance |
| `./docs/product.md` | Jobs and failures per actor | Single-actor acceptance, screens, threats |
| `./docs/testing.md` | Which test proves which requirement | Bare test-path list |
| `./docs/tech.md` | Why this stack, constraints, rejected options | Layer diagrams, data flow |
| `./docs/directory.md` | Allowed names, forbidden paths | Tree dumps |
| `./docs/pattern.md` | Lint/format quality design (tools, gates, why, what is not linted) | Indent/quotes, pasted config |
| `./docs/security.md` | Threats, secrets, permissions | Deploy, jobs |
| `./docs/problems.md` | Pitfalls, known docs↔code drift | Restating AGENTS bans |
| `./docs/references.md` | Pointers before searching | Copied bodies |
| `./docs/maintenance.md` | Deploy, config, monitoring | App design, threat source |
| `./docs/guidance.md` | Index when the tree is large | Spec source; never `docs/README.md` |
| `./DESIGN.md` | What is seen / operated | State, data flow; logo-to-3D headings without source |
| `./ROADMAP.md` | What / when / how far (**or** issues, one side) | Duplicating requirements; undated horizon buckets |
| `./docs/archive/` (optional) | Retired docs kept for history | Live intent; second spec source |
| `README` / `CONTRIBUTING` | Human door; runtime quotes only (see Placement) | Intent source; root scripts copied into every package |

Diagrams only when they carry the file's job. Duplicate tables: link. Split only when the load table requires [`references/bloat.md`](references/bloat.md); add `guidance.md` only per the Minimal profile.

**`docs/archive/`:** Create only when the user asks or the tree already has one. Archived files are not intent sources; Sync and navigation ignore them.

---

## Bootstrap

Interview if README/spec only; else read evidence, then ask only Unknowns.

**Interview (2-3 at a time):** source for commands / defaults / public surface; owner per topic.

**Evidence:** every present manifest (`package.json`, `Cargo.toml`, `pyproject.toml`, `setup.py`, `go.mod`, `pom.xml`, `build.gradle*`). No `||` first-one. Monorepo: root vs package. README / AGENTS / CI if present. No `find | head` (later files can be the real source). Unlisted stack → its real manifest/CI.

**Example:** "Rust CLI, no docs, initialize." `Cargo.toml` + CI, no README → row 2. Read `cargo test`/`clippy` from CI, deps from the manifest. One question for unknown owner. Three files only; skip product/pattern. Report Skipped + Unknowns (release owner).

---

## Sync

Does not create `docs/` (that invents intent while quoting runtime). **Full** = every row in the table. **Post-ship** = rows the change set touched. **Targeted** = named file + its source. Read the runtime source, then patch only mismatches in the quote column. A **drift** in a `docs/` quote: patch it to match runtime; if the intent itself may be wrong, record it in `problems.md` and leave the intent untouched. No mismatch → "no drift" and stop. One topic unless a batch was requested or the route is Full or Post-ship.

| Runtime source | Extract | Quote (runtime axis; mismatch → patch) | Intent quote (Terms **drift**) |
|---|---|---|---|
| manifest | scripts, deps, entry, published artifacts | README / CONTRIBUTING install & deps | — |
| CI | test/lint/build commands | README / CONTRIBUTING commands | — |
| code / schema | runtime defaults, public surface | README flags/samples | `docs/` that restates the same facts |
| config template | values people copy | README samples | — |
| source layout | module roles | README map | architecture; names in directory.md |

Monorepo: root README ↔ root manifest; package README ↔ that package. Root scripts copied into every package make a wrong command canonical (NEVER). Polyglot: command source is the CI job that actually runs. Picking a "main language" is a silent Gaps resolution.

**Example:** "added `--dry-run` and one dependency, sync docs," no filename → row 7. Read sources; patch only README deps + flag (runtime quotes). `--dry-run` default false in code and true in `docs/` → **drift** (Terms). Report: Scope=post-ship / sources / patched=README, docs quote / drifts=--dry-run / Gaps=none.

---

## Reorganize

Named structural change to an existing tree — merge, dedup, rename, move, split — on explicit request; `docs/` exists, or the named files are root docs. Cosmetic re-cataloging on the agent's own initiative stays row 1 **Stop**.

- Ownership survives the move: same decision, new home. Renaming onto catalog names is the user's call, never the agent's.
- Facts do not change during a move; runtime quotes still follow the Sync table.
- Dedup: one fact, two files → owner per Placement; the loser becomes a link or dies. Two-runtime-source conflicts stay **Gaps**; do not silently pick.
- Clean cutover: every reference to a moved / merged / renamed / deleted file updates in the same pass (indexes, related-docs lists, cross-links); grep-verify zero stale links before reporting.
- Split only at a contract boundary with owner and source, per [`references/bloat.md`](references/bloat.md).

**Example:** "merge setup.md into architecture.md, rename test.md to testing.md" → row 3. Content moves under the surviving owner's headings, every link updates, the emptied file dies, report ownership decisions + Gaps.

---

## Add-topic

One contract row, owner + source, **and `docs/` already exists**. Do not rename onto catalog names. Rename steals ownership and looks like Bootstrap.

**Example (ok):** "added a UI, record the design," `docs/` exists → row 5 → one `DESIGN.md`. Do not touch architecture duties.

**Example (no):** "add pattern.md," no `docs/` → row 2, never row 5. After three files, Minimal profile decides pattern.md.

---

## Write into AGENTS.md

Keep this block short.

- Read `AGENTS.md` → matching `docs/*` only
- Intent in `docs/`; runtime in code. Conflict → code; then drift fix or `problems.md`
- Requirement add/remove is human except factual drift sync

---

## NEVER

- `docs/tasks.md` / `docs/README.md`: live work in issues/ROADMAP; index is `guidance.md`
- Guess commands, deps, or defaults: the lie becomes the next source
- Rename / split / overwrite existing docs to fit the catalog on the agent's own initiative: ownership dies and the new name looks like Bootstrap coverage. A user-named structural change runs **Reorganize** instead
- Rewrite or reword a README on Targeted beyond the mismatched quotes: the diff must stay limited to what a source contradicts
- Change code defaults while "fixing" docs: mixed diffs hide both
- Lint/format essays in AGENTS / paste tool config into `pattern.md`: AGENTS stops being the entry; config files own the bits, `pattern.md` owns why the gate exists
- Agent spec in root README/DESIGN/ROADMAP: humans leave; agents miss `docs/`
- Distribute root scripts to every package (monorepo): a root command that fails in a package becomes that package's documented command
- Invent a tree when a path is unreadable, or treat an external URL as a source/**Gaps**: the guess or the web becomes the next session's truth

---

## Verify (all that apply, or not done)

- Every written claim traces to a path read this session; else delete or Unknowns
- Links: State table (relative missing vs external)
- Bootstrap: Skipped + why; if README was touched, AGENTS / docs remain reachable
- Sync: no out-of-scope prose; no code/config edits unless asked
- Add-topic: new content matches contract Role only; nothing from that row's **Does not** column
- Reorganize: facts unchanged in moves; every ownership decision listed; zero stale links after cutover

Failed item → **blocked**: which check, truth vs docs, human must choose?

## Report

- **Stop**: Stopped (reason)
- **Bootstrap**: Created / Skipped (why) / Sources+owners / Unknowns
- **Sync**: Scope (`full` \| `targeted` \| `post-ship`) / sources read / Files patched / Drifts fixed / Gaps
- **Add-topic**: Created (path) / Skipped (why) / source+owner
- **Reorganize**: moved / merged / renamed / deleted / links updated / ownership decisions / Gaps
- **Trace**: claim → source path
