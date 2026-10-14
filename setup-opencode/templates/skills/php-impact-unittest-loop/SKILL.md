---
name: php-impact-unittest-loop
description: 'Analyze impact scope, auto-generate PHPUnit test cases, and loop until 90% coverage for PHP source code.'
---

# PHP Impact Unittest Loop

Use this skill after PHP source changes are complete and the user requests a retest, an impact assessment, or higher coverage.

## 1. Analyze impact scope (Impact)

Use `git status` and `git diff -U0` to classify changed source files and changed lines.
Match git diff changes against the PHP file structure to pinpoint the exact modified Class and Method.
Build an impact assessment table: File / Function (Method) / Corresponding API / Risk level (HIGH/MED/LOW).

## 2. Determine test targets (Target)

Specify the exact functions and APIs to test, following these rules:
- Include directly changed functions/methods (identified in step 1).
- Include callers or callees of the changed function within 1 hop.
- Include API/Controller handlers directly related to the changed logic flow.
- Exclude auto-generated code, framework boilerplate, or migration/config files.

## 3. Create tests

Write tests with PHPUnit.
Place test files under `tests/` (e.g. `tests/Unit/` or `tests/Feature/`) mirroring the source directory structure (`src/` or `app/`). Test file names must carry the `Test.php` suffix.
Mock external dependencies with PHPUnit `createMock()` or `createStub()` (or Mockery if the project requires it).
Every changed logic branch (branch/if-else) must have covering test cases:
- Happy path
- Null or invalid values
- Error throwing (Exception)
- Boundary values

## 4. Run selective tests

Run tests only for affected Classes/Methods with the `--filter` flag. Avoid the full test suite.
Enable a coverage driver extension (Xdebug or PCOV) to collect measurements.
- Using PCOV: `php -d pcov.enabled=1 vendor/bin/phpunit --filter "TestClassName" --coverage-clover clover.xml --coverage-html coverage/`
- Using Xdebug: `XDEBUG_MODE=coverage vendor/bin/phpunit --filter "TestClassName" --coverage-clover clover.xml --coverage-html coverage/`

## 5. Coverage improvement loop (Loop-until-90)

Read the `clover.xml` report. Find the matching `<file>`, `<class>`, `<line>`, and `<metrics>` tags (note: Clover XML has no dedicated `<method>` tag; a method is a `<line type="method" name="...">`).
Evaluate Statement and Method percentages from `<metrics>` attributes or `<line>` counts: `(coveredstatements / statements) * 100` and `(coveredmethods / methods) * 100`.
Done criteria: Statements (line coverage) and Branch/Path coverage (if any) above 90%.
If below 90%, add test cases for the missing cases (unhit lines), then rerun the PHPUnit command with `--filter` and `--coverage-clover`.
Maximum 5 iterations. Each iteration, log: iteration number / missing coverage % / specific uncovered lines.

## 6. Finish or stop (Stop-and-ask)

Stop the loop and ask the user when any of these holds:
- A business-logic bug is found that breaks the app.
- Legacy source is too complex or has hidden dependencies that break mocking (untestable code).
- Coverage does not improve for 2 consecutive iterations.
When done (90% reached or forced stop per the conditions above), archive the report exactly once at `evidence/php-final-coverage.zip`. Never archive per iteration.
When stopping early, state the cause clearly with the PHPUnit error message or the blocking code.

## Output

```markdown
# PHP Impact Test Loop Result

## Impact analysis table
| File | Function (Method) | API | Risk level (HIGH/MED/LOW) |
|------|--------------|-----|------------------------------|

## Retest list
- ClassName::method1 (Selection reason)
- ClassName::method2 (Selection reason)

## Clover results
- Statements: X%
- Methods: Y%
- Status: PASS/FAIL (90% threshold)

## Iteration log
- Iteration 1: X% statements. Missing: if branch at line 45.
- Iteration 2: Y% statements. Missing: exception catch at line 60.
```

## Safety boundaries

- Do not modify original code in `src/` or `app/` just to bypass tests (unless the user agrees to a bug fix).
- Do not edit `phpunit.xml` to lower the project coverage bar.
- Keep the directory structure; only add files under `tests/`.
- Do not commit/push source code unprompted.
