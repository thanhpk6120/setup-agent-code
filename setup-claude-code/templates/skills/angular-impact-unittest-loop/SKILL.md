---
name: angular-impact-unittest-loop
description: 'Analyze impact scope, automatically generate Jasmine/Karma test cases, and run in a loop to achieve 90% coverage on Angular code.'
---

# Angular Impact Unittest Loop

Use this skill after Angular code changes are completed and the user requests retesting, impact evaluation, or increasing test coverage.

## 1. Analyze Impact Scope

Use `git status` or `git diff -U0` to classify changed source files and accurately map them to the corresponding components, services, or methods.
If GitNexus MCP is available, use `impact/context/trace` to inspect dependency graphs.
Build an impact assessment table: File / Function / Component or Service / Risk Level (HIGH/MED/LOW).

## 2. Identify Target Scope

Specify the concrete functions and components requiring tests based on the following rules:
- Include directly changed functions.
- Include callers or callees of the changed function within a 1-hop distance.
- User interaction: MUST ask and confirm if expanding the test scope or running entire files is necessary.

## 3. Generate Tests

Write tests using Jasmine and Angular `TestBed`.
Place test files in the same directory as the source file (`.spec.ts`).
- Use `TestBed.configureTestingModule` to set up modules.
- Mock dependencies (Services, Router, HttpClient) using `jasmine.createSpyObj`.
Every modified logic branch must have at least one test covering:
- Happy path.
- Boundary conditions (empty data, null/undefined, array boundary).
- Error flows (API failure, timeout, validation error).

## 4. Run Selective Tests & Collect Coverage

Run tests ONLY for the target file in headless mode with coverage flags enabled:
```bash
ng test --include="src/app/path/to/target.component.spec.ts" --no-watch --code-coverage --browsers=ChromeHeadless
```
Read the generated `lcov.info` file:
- Locate the section for the changed source file (`SF:...`).
- Extract line hits (`DA:line,count`) and branch hits (`BRDA:line,block,branch,taken`).
- Calculate coverage specifically for the modified lines/functions:
  `Coverage (%) = (Covered modified lines / Total modified lines) * 100`

## 5. Coverage Evaluation Loop

Evaluate coverage percentage on the modified code:
- **If Coverage >= 90%:** Stop the loop, archive evidence, and report results.
- **If Coverage < 90%:**
  1. Identify exact lines/branches missed from `DA:` or `BRDA:` lines with count 0.
  2. Write additional test cases targeting the uncovered logic branches.
  3. Re-run `ng test` and recalculate coverage.
  4. Repeat until reaching >= 90% or hitting maximum loop limit (default: 5 iterations).

## 6. Constraints & Anti-patterns

- **Forbidden to run the full test suite** unless explicitly requested by the user.
- **Forbidden to lower the threshold (90%)** requirement on modified code.
- **Forbidden to edit source code (`src/app`)** purely to make tests easier to pass without user permission.
- **Forbidden to delete old tests** to manipulate coverage percentages.
