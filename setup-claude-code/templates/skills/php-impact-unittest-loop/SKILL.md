---
name: php-impact-unittest-loop
description: 'Analyze impact scope, automatically generate PHPUnit test cases, and run in a loop to achieve 90% coverage on PHP code.'
---

# PHP Impact Unittest Loop

Use this skill after PHP code changes are completed and the user requests retesting, impact evaluation, or increasing test coverage.

## 1. Analyze Impact Scope

Use `git status` and `git diff -U0` to classify modified source files and changed lines.
Match diff changes with PHP file structures to accurately identify affected Classes and Methods.
Build an impact assessment table: File / Method / Corresponding API / Risk Level (HIGH/MED/LOW).

## 2. Identify Target Scope

Specify concrete functions and APIs requiring tests based on the following rules:
- Include directly changed functions/methods (identified in step 1).
- Include callers or callees of the changed function within a 1-hop distance.
- Include API/Controller handlers directly related to the modified logic flow.
- Exclude generated code, framework boilerplate, or migration/config files.

## 3. Generate Tests

Write tests using PHPUnit.
Place test files in the `tests/` directory (e.g. `tests/Unit/` or `tests/Feature/`) mirroring the source directory structure (`src/` or `app/`). Test file names must have the `Test.php` suffix.
Mock external dependencies using PHPUnit `createMock()` or `createStub()` (or Mockery if required by the project).
Every modified logic branch (if/else) must have covering test cases:
- Happy path
- Null or invalid values
- Thrown Exceptions
- Boundary values

## 4. Run Selective Tests

Only run tests for affected Classes/Methods using the `--filter` flag. Avoid running the full test suite.
Enable coverage driver (Xdebug or PCOV) to collect metrics:
- Using PCOV: `php -d pcov.enabled=1 vendor/bin/phpunit --filter "TestClassName" --coverage-clover clover.xml --coverage-html coverage/`
- Using Xdebug: `XDEBUG_MODE=coverage vendor/bin/phpunit --filter "TestClassName" --coverage-clover clover.xml --coverage-html coverage/`

## 5. Coverage Improvement Loop (Loop-until-90)

Read report file `clover.xml`. Locate corresponding `<file>`, `<class>`, `<line>`, and `<metrics>` elements (Note: Clover XML has no separate `<method>` element; methods are represented via `<line type="method" name="...">`).
Evaluate Statements and Methods percentage from `<metrics>` attributes or count `<line>` tags. Formula: `(coveredstatements / statements) * 100` and `(coveredmethods / methods) * 100`.
Passing criteria: Statements (Line coverage) and Branch/Path coverage (if available) greater than 90%.
If below 90%, add test cases for uncovered branches/lines, then re-run PHPUnit with `--filter` and `--coverage-clover`.
Limit to a maximum of 5 iterations. At each iteration, log: Iteration number / Missing coverage percentage / Specific uncovered lines.

## 6. Complete or Stop (Stop-and-ask)

Stop the loop and ask the user if any of the following conditions occur:
- Critical business logic defect detected that breaks application behavior.
- Legacy code is untestable by design or contains hidden dependencies causing mock failures.
- Coverage does not improve across 2 consecutive iterations.
When completing the procedure (successfully reaching 90% or stopping per above), compress the report into a ZIP file once at `evidence/php-final-coverage.zip`. Do not compress files at each iteration.
When stopping early, clearly present the root cause along with PHPUnit error logs or the blocking code snippet.

## Output

```markdown
# PHP Impact Test Loop Result

## Impact Table
| File | Method | API | Risk Level (HIGH/MED/LOW) |
|------|--------|-----|---------------------------|

## Retest List
- ClassName::method1 (Selection rationale)
- ClassName::method2 (Selection rationale)

## Clover Coverage Result
- Statements: X%
- Methods: Y%
- Status: PASS/FAIL (90% Threshold)

## Iteration Log
- Loop 1: Reached X% Statements. Missing: If-branch at line 45.
- Loop 2: Reached Y% Statements. Missing: Exception catch at line 60.
```

## Safety Boundaries

- Do not modify original code in `src/` or `app/` merely to bypass tests (unless the user approves bug fixes).
- Do not modify `phpunit.xml` configuration to lower the project coverage standards.
- Preserve directory structures; only add files inside `tests/`.
- Do not autonomously commit or push source code.
