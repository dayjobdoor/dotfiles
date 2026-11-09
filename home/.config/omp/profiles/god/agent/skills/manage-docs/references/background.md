## Catalog split

This catalog is not Diátaxis (tutorial / how-to / reference / explanation) or C4 zoom levels (Context / Container / Component / Code). It splits by who decides the fact, because agents treat any written file as the next session's source. C4 detail belongs as optional content inside `architecture.md` when sourced; this catalog does not mint C4-named files.

- **Entry vs intent vs runtime.** README is a human door. Install/commands/flags/deps/samples are runtime quotes of code/CI/manifest (mismatch → patch the quote). Goals and architecture belong in `docs/`. If README owns them, agents skip `docs/` and humans stop at the agent prose (mismatch with `docs/` → drift).
- **Same-axis Gaps vs cross-axis drift.** Two CIs disagree → Gaps (write neither). Code says `--dry-run` default false and `docs/` says true → drift (`docs/` quotes runtime). Do not freeze both as two truths.
- **One file, one decision.** Mixing "what ships" with "how it runs" or "how it looks" makes the next edit overwrite the wrong axis. `architecture.md` vs `directory.md` vs `tech.md` is that split (duties/flow vs names vs rejected options). Agent-only files split the same way: `AGENTS.md` decides how agents explore; `REVIEW.md` decides how an external reviewer reviews; neither restates intent docs.
- **Omit empty catalog rows.** A filename with no owner/source looks like coverage; later sessions treat the stub as truth.
- **Changelogs stay out.** History is mutable; intent docs are not a log.
