---
name: react-impact-unittest-loop
description: 'Analyze impact scope, auto-generate Vitest/Jest test cases, and loop until at least 90% coverage for changed React code.'
---

# React Impact Unittest Loop

Use this skill after React source changes to assess impact, write tests, and ensure new/modified code reaches at least 90% coverage.

**Important**: Vitest/Jest do not filter coverage by changed lines. You must get the changed-line list from git, run the matching test file, and extract coverage metrics for exactly those lines from the default lcov/json report.

## Natural workflow

### 1. Assess impact (Impact)
- Run `git diff -U0` or `git diff --name-only` to learn which files and lines changed.
- Map changed lines to the corresponding components, hooks, or functions.
- Determine the impact scope (nearest parent/child components, API calls).
- If the change is too complex or the test scope is unclear, stop and ask the user.

### 2. Write tests and mocks (Vitest/Jest)
- Create or update the test file next to the component/hook (e.g. `.test.tsx`).
- Mock boundaries such as APIs, DOM APIs, and external libraries with `vi.fn()`, `vi.spyOn()`, or `vi.mock()`. (With Jest, use `jest.fn/mock/spyOn`).
- Cover the changed logic branches: happy path, empty/null data, loading, and error.

### 3. Run selective tests and read coverage
- Run tests **only for changed files** for speed and isolation:
  - Vitest: `vitest run <file.test.tsx> --coverage --coverage.reporter=lcov --coverage.reporter=json` or `vitest related <file.tsx> --run --coverage --coverage.reporter=lcov --coverage.reporter=json`
  - Jest: `jest <file.test.tsx> --coverage --collectCoverageFrom="<file.tsx>"`
- Read the generated default report (e.g. `coverage/lcov.info` or `coverage/coverage-final.json`).
- Apply a filter script on lcov or coverage-final.json to compute Statement/Branch/Function coverage for exactly the **changed functions/lines**.

### 4. 90% optimization loop (Loop)
- If coverage of the changed code is below 90% (Statement and Branch), keep adding test cases.
- Maximum **5 iterations**.
- Each iteration, optionally open the HTML report (via an OS command or `npx serve coverage`) to analyze the gap.

### 5. Finish / stop and ask (Stop-and-ask)
- Archive evidence (coverage, log) **exactly once** into `evidence/react-final-coverage.zip` on 90% success or forced final stop.
- If stuck (untestable due to overly complex / tightly coupled components) or coverage stalls for 2 consecutive iterations.
- If the code has a logic bug.
- Stop immediately and report/ask the user, attaching the evidence file.
## Output Template

Report results in this format:

```markdown
# React Impact Test Loop Result

## 1. Impact scope
- Changed file: `src/components/MyComponent.tsx`
- Function/Component: `handleSubmit`
- Risk level: MED

## 2. Test changes
- Added file: `MyComponent.test.tsx`
- Covered cases: Happy path, Network Error.

## 3. Coverage results (changed functions/lines only)
- STATEMENT: X%
- LINE: Y%
- BRANCH: Z%
- FUNCTION: W%

## 4. Iteration log
- Iteration 1: 70% branch. Missing: API error branch.
- Iteration 2: 95% branch. Fully covered.

## 5. Evidence
- File: `evidence/react-final-coverage.zip`
```


## Safety Boundaries

- **Do not modify source (src/)** just to make code easier to test without user permission.
- **Do not lower the required threshold (90%)** for changed code.
- **Do not delete old tests** to beautify or manipulate coverage rates.
- **Do not run the full test suite** unless the user requests it (wastes time, pollutes logs).