## DESIGN.md structure (Google format)

**Spec:** [google-labs-code/design.md](https://github.com/google-labs-code/design.md) (`docs/spec.md`). Spec is alpha; tokens normative, prose is how to apply them.

Write a section or token only from an implementation or design source this session (screens, tokens, CSS, code, mock). No source → omit. Empty headings and invented marks are coverage. Prefer a specific reference over adjective lists ("modern, clean").

### File layers

1. **YAML front matter** (`---` … `---`) — machine-readable tokens. Normative values.
2. **Markdown body** — `##` sections with rationale. Tokens tell *what*; prose tells *why* / *how*.

If the user asked for `DESIGN.md` but not structure, write only what is seen/operated from evidence. Do not expand into the full schema.

### Token schema (front matter)

```yaml
version: <string>          # optional; current: "alpha"
name: <string>
description: <string>      # optional
omitted: <string[] | {section, reason?}[]>  # intentional absences (suppresses missing-section lint)
colors:
  <token-name>: <Color>    # any CSS color; hex preferred
typography:
  <token-name>:            # fontFamily, fontSize, fontWeight, lineHeight, letterSpacing, fontFeature?, fontVariation?
    fontFamily: …
    fontSize: …
rounded:
  <scale-level>: <Dimension>   # xs|sm|md|…; px|em|rem
spacing:
  <scale-level>: <Dimension | number>
components:
  <component-name>:
    <prop>: <string | {path.to.token}>
```

- Token refs: `{colors.primary}` (primitive); components may ref composites (`{typography.label-md}`).
- Component props: `backgroundColor`, `textColor`, `typography`, `rounded`, `padding`, `size`, `height`, `width`. Variants = separate keys (`button-primary-hover`).
- Unknown section headings: preserve. Duplicate `##` section: reject. Unknown component props: accept with warning.

### Body section order

Present sections must keep this order (aliases OK). Omit irrelevant ones; list intentional skips under `omitted:`.

| # | Section | Alias |
|---|---|---|
| 1 | Overview | Brand & Style |
| 2 | Colors | |
| 3 | Typography | |
| 4 | Layout | Layout & Spacing |
| 5 | Elevation & Depth | Elevation |
| 6 | Shapes | |
| 7 | Components | |
| 8 | Do's and Don'ts | |

Axes per section (not a stamp TOC — only with evidence):

- **Overview**: personality, audience, emotional register; one concrete reference beats adjectives.
- **Colors**: roles (`primary` / `secondary` / `tertiary` / `neutral` …) with hex + why; contrast only if specified.
- **Typography**: families, roles (display / headline / body / label), sizes/weights in source.
- **Layout**: grid / fluid / safe-area; spacing scale from source.
- **Elevation & Depth**: shadows, blur, layering only if shipped.
- **Shapes**: radii / geometry from tokens or CSS.
- **Components**: reused pieces named in code; map to tokens via `{…}` refs.
- **Do's and Don'ts**: intentional negatives; strong Overview reference already carries many "don'ts".

### Checks (when tooling is available)

```bash
npx @google/design.md lint DESIGN.md
```

Priority findings: `broken-ref` (error), `missing-primary` / `missing-typography` / `contrast-ratio` / `section-order` (warning). Do not invent tokens to silence lints — use `omitted:` with a reason, or leave the token unknown (Unknowns).
