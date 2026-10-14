---
name: angular-impact-unittest-loop
description: 'Analyze impact scope, auto-generate Jasmine/Karma test cases, and loop until 90% coverage for Angular source code.'
---

# Angular Impact Unittest Loop

Use this skill after Angular source changes are complete and the user requests a retest, an impact assessment, or higher coverage.

## 1. Analyze impact scope (Impact)

Use `git status` or `git diff -U0` to classify changed source files and map them precisely to the corresponding components, services, or methods.
If GitNexus MCP is available, run `impact/context/trace` to scan the dependency graph.
Build an impact assessment table: File / Function / Component or Service / Risk level (HIGH/MED/LOW).

## 2. Determine test targets (Target)

Specify the exact functions and components to test, following these rules:
- Include directly changed functions.
- Include components/services that call (callers) or are called by (callees) the changed function within 1 hop.
- User interaction: you MUST ask for confirmation before expanding the test scope or running the full file.

## 3. Create tests

Write tests with Jasmine and Angular `TestBed`.
Place test files in the same directory as the source file (`.spec.ts`).
- Use `TestBed.configureTestingModule` to set up the module.
- Mock dependencies (Services, Router, HttpClient) via `jasmine.createSpyObj`.
Every changed logic branch must have at least one corresponding test case:
- Happy path
- Null/undefined values, empty data
- Error throwing (exception/HttpErrorResponse)
- Branch states (if/else)

## 4. Run selective tests

Run tests individually on newly created or changed files. Do not run the full test suite.
Run: `ng test --include="<spec_file_path>" --no-watch --code-coverage --browsers=ChromeHeadless`
If the full suite must run, get user confirmation first.

## 5. Coverage improvement loop (Loop-until-90)

Read the default coverage report at `coverage/<project-name>/lcov.info` or `coverage/<project-name>/index.html`.
Collect the `Lines`, `Functions`, and `Branches` metrics for the functions changed per the git diff.
Done criteria: 90% coverage on all 3 metrics for the changed functions.
If not met, only fix/add test cases, rerun the `ng test` selective run, and re-check lcov.
Maximum 5 iterations. Each iteration, log: iteration number / current coverage / missing branch.

## 6. Stop and ask

Stop the loop and ask the user if:
- A critical business-logic bug is found.
- The source is hard or impossible to test (untestable code) due to hidden dependencies or design.
- Coverage does not change/increase for 2 consecutive iterations.
Present the question clearly with supporting logs or code.

When done (90% coverage) or when stopping, archive the coverage report exactly once into `evidence/angular-final-coverage.zip`.

## Output

```markdown
# Angular Impact Test Loop Result

## Impact analysis table
| File | Function / Method | Component / Service | Risk level (HIGH/MED/LOW) |
|------|-------------------|---------------------|------------------------------|

## Retest list
- Component.method1 (Selection reason)
- Service.method2 (Selection reason)

## Coverage results
- Functions: X%
- Lines: Y%
- Branches: Z%

## Test evidence
- Report file: coverage/<project-name>/index.html
- Archived evidence: evidence/angular-final-coverage.zip

## Iteration log
- Iteration 1: X% branches. Missing: if(data == null) branch.
- Iteration 2: Y% branches. Missing: catchError HTTP 500 branch.
```

## Safety boundaries

- Do not modify business source in `src/app` during the test loop.
- Do not lower the required coverage threshold (90%) in `angular.json` or `karma.conf.js` unless instructed.
- Do not delete old test cases to fake coverage.
- Do not commit source code unless requested.