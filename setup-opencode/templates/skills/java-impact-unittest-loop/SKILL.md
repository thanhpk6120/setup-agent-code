---
name: java-impact-unittest-loop
description: 'Analyze impact scope, auto-generate JUnit/Mockito test cases, and loop until 90% coverage for Java source code.'
---

# Java Impact Unittest Loop

Use this skill after Java source changes are complete and the user requests a retest, an impact assessment, or higher coverage.

## 1. Analyze impact scope (Impact)

Use `git status` or `git diff --name-only` to classify changed source files.
If GitNexus MCP is available, run `impact/context/trace` to scan the dependency graph.
Otherwise, analyze manually in layer read order: `controller -> service -> repository -> entity`.
Build an impact assessment table: File / Function / Corresponding API / Risk level (HIGH/MED/LOW).

## 2. Determine test targets (Target)

Specify the exact functions and APIs to test, following these rules:
- Include directly changed functions.
- Include callers or callees of the changed function within 1 hop.
- Include API handlers directly related to the changed logic flow.
- Exclude auto-generated code or system configuration classes.

## 3. Create tests

Write tests with JUnit5 and Mockito.
Place test files under `src/test` with a package structure mirroring `src/main`. Test file names must carry the `Test` suffix.
Mock system boundaries such as Database, HTTP client, or Message Queue.
Every changed logic branch must have at least one corresponding test case:
- Happy path
- Null values
- Empty data
- Error throwing (exception)
- Access permission

## 4. Run selective tests

Run tests individually on newly created or changed files; never run the full test suite unless the impact spans the whole system.
With Maven: run `mvn -Dtest=[TestClassName] -Dsurefire.failIfNoSpecifiedTests=false test`, then `mvn jacoco:report`.
With Gradle: run `gradle test --tests "[Package.TestClassName]"`, then `gradle jacocoTestReport`.

## 5. Coverage improvement loop (Loop-until-90)

Read the report at `target/site/jacoco/jacoco.xml` or `build/reports/jacoco/test/jacocoTestReport.xml`.
Collect counters (INSTRUCTION, LINE, BRANCH with MISSED and COVERED) for the affected classes.
Compute the percentage as (COVERED / (MISSED + COVERED)).
Done criteria: over 90% on all 3 counter types, or at minimum on INSTRUCTION and BRANCH.
If not met, only fix/add test cases, then rerun the test and jacoco commands.
Maximum 5 iterations. Each iteration, log: iteration number / missing coverage ratio / uncovered branches.

## 6. Stop and ask

Stop the loop and ask the user when any real stop condition holds:
- A critical business-logic bug is found that could affect production.
- The source is untestable by design.
- Coverage does not increase for 2 consecutive iterations.
When stopping, present the question clearly with concrete evidence from logs or code.

## 7. Package results (Zip evidence)

Creating the ZIP must be the final step after exiting the coverage improvement loop.
Create the `evidence/` directory and archive the JaCoCo report directory (e.g. `target/site/jacoco/` or `build/reports/jacoco/`) as `evidence/java-final-coverage.zip`.

## Output

```markdown
# Java Impact Test Loop Result

## Impact analysis table
| File | Function | API | Risk level (HIGH/MED/LOW) |
|------|-----|-----|------------------------------|

## Retest list
- Class.method1 (Selection reason)
- Class.method2 (Selection reason)

## JaCoCo results
- INSTRUCTION: X%
- LINE: Y%
- BRANCH: Z%

## Iteration log
- Iteration 1: X% branches. Missing: null-check branch.
- Iteration 2: Y% branches. Missing: exception-check branch.

## Test evidence
- Archived evidence: evidence/java-final-coverage.zip
```

## Safety boundaries

- Do not modify source code in `src/main` during the test loop.
- Do not lower the required coverage threshold (90%).
- Do not delete old test cases just to inflate coverage.
- Do not commit or push source code unless the user requests it.