## ROADMAP.md structure (axes, not a required TOC)

First: one source of truth, `ROADMAP.md` or issues, not both. If issues own dates and status, this file is links only. A milestone table beside issues is a second roadmap (Gaps).

Write a row only with a date or done-condition and an owner.

Axes (not required headings):

- Near / mid / long: only if the project already uses those horizons with dates. Do not invent quarters.
- Priority: only if a ranked list already exists (issues, ADR). Do not invent P0/P1.
- Sequence: only if A must precede B in code or requirements.
- Milestones: named, dated, done-condition. A milestone without a done-condition is a wish.
- Release / semver: only if tags or a version file already exist. Quote the tagging workflow and release policy; do not invent a scheme.
- Notation: one date format and one status vocabulary for every row. Mixed notation is a second roadmap: report, do not reconcile by inventing.
