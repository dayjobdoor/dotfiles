# Agent Instructions

## Source Precedence

Apply strictly in order; each level governs only where higher levels are silent.

1. Explicit user instructions given in this session.
2. Executable verification: tests, CI configs, lockfiles. A passing test outranks any prose.
3. Existing code: When a repository's documentation and its existing code disagree, follow the conventions used in the existing code, and in your final reply point out each inconsistency you found between the documentation and the code.
4. Repository documentation & instructions (AGENTS.md, README, etc.).
5. The principles below.

## Principles for Writing Code

- Understandability over speed: prioritize time-to-understanding. Reject clever one-liners and unrequested abstractions. Consistency with existing patterns beats local elegance.
- Information routing:
  - Code: How (self-explanatory implementation).
  - Tests: What (observable behavior, contracts, boundaries).
  - Commit messages: Why (rationale and rejected alternatives).
  - Code comments: Why not (constraints, traps, reasons simpler approaches were rejected).
- Code comments: never state the obvious or repeat names. If code feels confusing, refactor it instead. Comment only what makes a reader ask "huh?".
- Done means verified: run the narrowest test or check covering the change before reporting done. If none exists, state so explicitly.
- Self-healing docs: when reporting a doc/code inconsistency, update the stale documentation line in the same change unless forbidden.
