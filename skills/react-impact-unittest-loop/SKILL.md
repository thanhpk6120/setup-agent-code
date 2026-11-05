---
name: react-impact-unittest-loop
description: 'Analyze impact scope, automatically generate Vitest/Jest test cases, and run in a loop to achieve at least 90% coverage on changed React code.'
---

# React Impact Unittest Loop

Use this skill after React source code changes to assess impact, write tests, and ensure new/modified code achieves at least 90% coverage.

**Important Note**: Vitest/Jest do not natively filter coverage by modified git lines. You must extract the modified line range via git, run the matching test file, and parse coverage metrics for those exact lines from default lcov/json report files.

## Workflow

### 1. Assess Impact Scope
- Run `git diff -U0` or `git diff --name-only` to identify modified files and changed line numbers.
- Map modified lines to corresponding components, hooks, or functions.
- Determine impact scope (immediate parent/child components, API calls).
- If changes are overly complex or ambiguous, stop and ask the user.

### 2. Write Tests & Mocks (Vitest/Jest)
- Create or update test files adjacent to the component/hook (e.g. `.test.tsx`).
- Mock boundaries like APIs, DOM APIs, and external libraries using `vi.fn()`, `vi.spyOn()`, or `vi.mock()` (with Jest, use `jest.fn/mock/spyOn`).
- Cover all logic branches of the change: Happy path, empty/null data, loading state, and error handling.

### 3. Run Selective Tests & Parse Coverage
- Run tests **only for the modified file** for speed and isolation:
  - Vitest: `vitest run <file.test.tsx> --coverage --coverage.reporter=lcov --coverage.reporter=json` or `vitest related <file.tsx> --run --coverage --coverage.reporter=lcov --coverage.reporter=json`
  - Jest: `jest <file.test.tsx> --coverage --collectCoverageFrom="<file.tsx>"`
- Read generated report files (`coverage/lcov.info` or `coverage/coverage-final.json`).
- Apply filtering script on the lcov or coverage-final.json file to calculate Statement/Branch/Function coverage strictly for the **modified lines/functions**.

### 4. 90% Optimization Loop
- If coverage on the changed code is below 90% (Statement and Branch), add additional test cases.
- Limit to a maximum of **5 iterations**.
- In each iteration, open the visual HTML report (`npx serve coverage`) to identify uncovered branches.

### 5. Completion / Stop and Ask
- Archive evidence (coverage, logs) **once only** into `evidence/react-final-coverage.zip` when reaching 90% or upon final termination.
- If stuck (untestable due to tight coupling), or coverage does not increase across 2 consecutive iterations:
- Stop immediately and report to the user with the evidence archive.

## Output Template

```markdown
# React Impact Test Loop Result

## 1. Impact Scope
- Changed file: `src/components/MyComponent.tsx`
- Function/Component: `handleSubmit`
- Risk level: MED

## 2. Test Changes
- Added file: `MyComponent.test.tsx`
- Covered cases: Happy path, Network Error.

## 3. Coverage Result (Calculated strictly on changed lines)
- STATEMENT: X%
- LINE: Y%
- BRANCH: Z%
- FUNCTION: W%

## 4. Iteration Log
- Loop 1: Reached 70% branch. Missing: API error branch.
- Loop 2: Reached 95% branch. Fully covered.

## 5. Evidence
- File: `evidence/react-final-coverage.zip`
```

## Safety Boundaries

- **Forbidden to modify source code (`src/`)** purely to make code easier to test without user permission.
- **Forbidden to lower the required threshold (90%)** on modified code.
- **Forbidden to delete old tests** to inflate coverage percentages.
- **Forbidden to run the full test suite** without user request.
