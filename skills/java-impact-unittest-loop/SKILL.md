---
name: java-impact-unittest-loop
description: 'Analyze impact scope, automatically generate JUnit/Mockito test cases, and run in a loop to achieve 90% coverage on Java code.'
---

# Java Impact Unittest Loop

Use this skill after Java code changes are completed and the user requests retesting, impact evaluation, or increasing test coverage.

## 1. Analyze Impact Scope

Use `git status` or `git diff --name-only` to classify modified source files.
If GitNexus MCP is available, use `impact/context/trace` to inspect dependency graphs.
Otherwise, perform manual analysis following layer read order: `controller -> service -> repository -> entity`.
Build an impact assessment table: File / Method / Corresponding API / Risk Level (HIGH/MED/LOW).

## 2. Identify Target Scope

Specify concrete functions and APIs requiring tests based on the following rules:
- Include directly modified functions.
- Include callers or callees of the changed function within a 1-hop distance.
- Include API handlers directly related to the modified logic flow.
- Exclude generated code and system configuration classes (config).

## 3. Generate Tests

Write tests using JUnit 5 and Mockito.
Place test files in the `src/test` directory mirroring the package structure of `src/main`. Test file names must have the `Test` suffix.
Mock system boundaries such as Databases, HTTP clients, or Message Queues.
Every modified logic branch must have at least one corresponding test case:
- Happy path
- Null values
- Empty data
- Thrown exceptions
- Access permissions

## 4. Run Selective Tests

Execute tests individually on newly created or modified files. Running the full test suite is forbidden unless impact spreads system-wide.
With Maven: use `mvn -Dtest=[TestClassName] -Dsurefire.failIfNoSpecifiedTests=false test`, then run `mvn jacoco:report`.
With Gradle: use `gradle test --tests "[Package.TestClassName]"`, then run `gradle jacocoTestReport`.

## 5. Coverage Evaluation Loop (Loop-until-90)

Read report file `target/site/jacoco/jacoco.xml` or `build/reports/jacoco/test/jacocoTestReport.xml`.
Collect counters: INSTRUCTION, LINE, BRANCH (MISSED and COVERED) for affected classes.
Calculate percentage: `COVERED / (MISSED + COVERED) * 100`.
Passing criteria: Exceeding 90% across all 3 counter types, or at minimum for INSTRUCTION and BRANCH.
If below 90%, only modify and add test cases, then re-run test and jacoco commands.
Limit to a maximum of 5 iterations. At each iteration, log: Iteration number / Missing coverage percentage / Uncovered branches.

## 6. Stop and Ask

Stop the loop and ask the user if any of the following true stopping conditions are met:
- Severe business logic defect detected that may affect production.
- Code is untestable by design.
- Coverage does not increase across 2 consecutive iterations.
When stopping, present the inquiry clearly along with concrete evidence from logs or code.

## 7. Package Results (Zip Evidence)

Creating the ZIP must be the final step after exiting the coverage loop.
Create `evidence/` directory and compress the JaCoCo report directory (e.g.: `target/site/jacoco/` or `build/reports/jacoco/`) as `evidence/java-final-coverage.zip`.

## Output

```markdown
# Java Impact Test Loop Result

## Impact Table
| File | Method | API | Risk Level (HIGH/MED/LOW) |
|------|--------|-----|---------------------------|

## Retest List
- Class.method1 (Selection rationale)
- Class.method2 (Selection rationale)

## JaCoCo Result
- INSTRUCTION: X%
- LINE: Y%
- BRANCH: Z%

## Iteration Log
- Loop 1: Reached X% branches. Missing: Null-check branch.
- Loop 2: Reached Y% branches. Missing: Exception-check branch.

## Evidence
- Archive: evidence/java-final-coverage.zip
```

## Safety Boundaries

- Do not modify source code in `src/main` during test loops.
- Do not lower the required coverage threshold (90%).
- Do not delete existing test cases to artificially inflate coverage rates.
- Do not autonomously commit or push source code without user request.
