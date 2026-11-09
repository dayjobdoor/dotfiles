---
name: testing-principles
description: Behavior-focused testing guidance for TypeScript/JavaScript tests (Vitest, Jest, Testing Library). Use when writing, reviewing, restructuring, or deleting tests; choosing unit/integration/smoke/E2E boundaries; consolidating over-split suites; or cleaning up low-signal agent-generated tests (magic-number asserts, tiny wrappers, stale bug histories).
---

# Testing Principles

Use **contract-first** tests: identify observable behavior, choose the smallest test level that proves it, then keep setup, actions, assertions, and side effects in one legible workflow.

## Workflow model

Model each test on a **manual tester's workflow**, not on assertion count.

- One user-facing workflow or state transition → one top-level `test(...)`.
- **Single Arrange** per test; multiple Acts and Asserts are fine when they belong to the same workflow.
- Keep intermediate-state assertions inside the workflow that produces them — modern runners show which assertion failed with enough context that mechanical "one assertion per test" splits are unnecessary and harmful.
- Re-render the same component for prop updates inside one test; do not mount it twice in the same test for separate concerns.

## Test-level choice

Choose the smallest level whose failure class covers the risk under test:

| Test level | Failures only this level catches |
|---|---|
| Unit | Wrong results from pure logic or isolated handlers |
| Integration/server | Miswired interaction across real local boundaries — persistence, middleware, handlers |
| Smoke / contract | Transport, auth, or session failures invisible in-process |
| E2E | Browser-only failures: rendering, navigation, real input |

Keep E2E to a few important happy paths. Add a slower test only when its boundary catches a failure the smaller test cannot observe.

## Test design

- Name intent plainly, including expected behavior: `auth handler returns 400 for invalid JSON`.
- Split independent contracts into separate tests; combine assertions when they depend on the same rendered object, request, response, or state transition.
- Inline setup per test; build factories that return ready-to-run objects; use `using`/`Symbol.dispose` only when cleanup is real.
- Start from observable contract; keep tests offline with local fakes and fixtures, not public internet or third-party services.
- Assert structured output, user-visible outcomes, or stable public contracts.
- Add regression tests when failure is plausible and the flow justifies maintenance cost — not bug histories whose contract value has lapsed.
- Delete or merge **low-signal tests**: tiny wrappers, magic-number asserts, impossible edge cases, and suites that only duplicate what a shorter workflow test already proves. More green checks ≠ more confidence.

## Console output

When the project guards console output in global test setup, unexpected `console.error` and `console.warn` should fail tests unless explicitly handled. Keep allowlists narrow so unrelated regressions stay visible. If the project has no guard, add one in global setup before allowlisting anything — never silence ad hoc inside a single test.

When logging is part of the contract, assert it with the project's exported spies:

```ts
test('retries on 429', () => {
  consoleWarn.mockImplementation(() => {}); // project console spy from test setup
  retry(request);
  expect(consoleWarn).toHaveBeenCalledWith('http.retry', expect.any(Error));
});
```

Prefer stable first-argument tags plus `expect.any(Error)`; assert call count when deterministic.

When the guard fails a test, classify the failing tag before silencing it:

| Failing output is | Action |
|---|---|
| Contract logging | Assert with the project's `consoleError`/`consoleWarn` spies as above |
| Expected incidental noise | Use the project's allowlist helper with exact expected message tags |
| Known runtime/tooling noise | Use the project's scoped runtime-noise silencer, if one exists |
| None of these | Investigate — an unexpected warning is often the regression the guard exists to surface |

## Side-effect sinks

When global test setup mocks a side-effect sink (audit log, metrics, analytics), import the shared spy and assert expected events, including `not.toHaveBeenCalled()` when no event is expected.

When testing the real pipeline, opt out with `vi.unmock()` on the **same module id the setup file registered** — read the setup file or spy module comment for the exact path/alias.

When overriding other exports from that module, declare a local `vi.mock(...)` and route the sink function back through the shared spy so per-test assertions stay consistent.

## Running tests

Use the project's documented test command for the boundary you changed. Prefer targeted file or project paths when diagnosing failures — broad patterns often pull in slow smoke or E2E suites unrelated to the change.

## NEVER

- **NEVER** split one assertion per test mechanically. Shared setup across tests leaks mutable state and makes failures order-dependent; modern runners already pinpoint failing assertions inside one workflow test.
- **NEVER** mount the same component twice in one test for separate concerns. Prop-update re-renders inside one workflow are fine.
- **NEVER** blanket-mock console. It hides the unexpected warnings and errors the guard exists to surface; scope mocks to expected noise.
- **NEVER** share mutable state between tests. Leaked state makes failures order-dependent.
- **NEVER** test guarantees already provided by TypeScript's type system — a failing type check already fails CI.
- **NEVER** assert incidental prose, tool descriptions, usage hints, warnings, or configuration strings — they are unstable contracts.
- **NEVER** keep low-signal tests for coverage. Tiny wrappers, magic-number asserts, and stale bug-history tests erode suite trust without catching real regressions.
- **NEVER** run broad test path patterns when targeted paths suffice. They waste time and often match unrelated slow suites.

## Completion check

Before finishing a test change, verify:

1. Each test's level is justified by the boundary it observes.
2. Console and side-effect assertions are made or explicitly allowlisted.
3. The appropriate project test command ran for the changed boundary; if unavailable, document a targeted substitute.
