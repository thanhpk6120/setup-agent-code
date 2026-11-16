---
name: surefire-test
description: Use when the user asks to run isolated Java or JUnit tests with Maven Surefire, target a specific test class or method, avoid broad Maven lifecycle commands, reduce unrelated compile noise, or handle suspected stale target/test-classes bytecode.
---

# Surefire Test

## Overview
Use the narrowest Maven Surefire command possible. Prefer `surefire:test` with `-Dtest=...` and `-f <pom.xml>` over `mvn test` or `mvn verify` when the user wants fast, isolated feedback.

For larger Java testing work, prefer the existing `java-tester` agent. For one-off targeted runs, answer directly with the exact command.

## When to Use
- Run one Java test class or one test method
- Avoid running the full Maven test lifecycle
- Current working directory is unclear, unstable, or not the project root
- The user wants compile-heavy work deferred until later
- The user wants the narrowest possible feedback loop
- Do not use this skill when the user explicitly wants the full test suite or the full Maven lifecycle

## Workflow
1. Identify the correct `pom.xml` and prefer `-f` with an absolute path.
2. Choose the narrowest selector:
   - class: `-Dtest=MyServiceTest`
   - method: `-Dtest=MyServiceTest#shouldReturnSuccess`
   - multiple classes: `-Dtest=MyServiceTest,UserServiceTest`
3. If stale bytecode is suspected, or the selected test was just added or edited, confirm the test class or method is present in source before trusting existing compiled outputs.
4. Treat compiled outputs as current only when they are known to match the selected source.
5. If compiled outputs are current, run Surefire directly:
   - `mvn -f "D:/path/to/pom.xml" -Dtest=MyServiceTest surefire:test`
6. If stale bytecode is suspected and you need a true TDD red from the current source, run the smallest lifecycle command that recompiles before execution:
   - `mvn -f "D:/path/to/pom.xml" -Dtest=MyServiceTest test`
7. If the project is multi-module, add `-pl <module>` and only add `-am` when required.
8. If the user explicitly wants to avoid a separate compile step, do not run `compile` first. State the limitation clearly instead of hiding it.

## Quick Reference
| Need | Command |
| --- | --- |
| One test class | `mvn -f "D:/path/to/pom.xml" -Dtest=MyServiceTest surefire:test` |
| One test method | `mvn -f "D:/path/to/pom.xml" -Dtest=MyServiceTest#shouldReturnSuccess surefire:test` |
| Multiple classes | `mvn -f "D:/path/to/pom.xml" -Dtest=ATest,BTest surefire:test` |
| Suspected stale bytecode | `mvn -f "D:/path/to/pom.xml" -Dtest=MyServiceTest test` |
| Suspected stale bytecode for one method | `mvn -f "D:/path/to/pom.xml" -Dtest=MyServiceTest#shouldReturnSuccess test` |
| One module only | `mvn -f "D:/path/to/pom.xml" -pl :module-artifact -Dtest=MyServiceTest surefire:test` |

## Common Mistakes
- Using `mvn test` when the user asked for an isolated run
- Relying on `cd` instead of `-f <pom.xml>`
- Claiming `surefire:test` guarantees zero compile work
- Trusting `surefire:test` after editing tests without considering stale `target/test-classes`
- Skipping a source check and assuming the selected test already exists in current source
- Running the full suite before trying the targeted command

## Important Limitation
`surefire:test` avoids the broader Maven lifecycle, but it still expects valid compiled outputs such as `target/classes` and `target/test-classes`. If those outputs are missing or stale, say so explicitly and offer the smallest follow-up command instead of pretending the run is fully isolated. When stale bytecode is suspected, or the selected test was just added or edited, and you need the current source to produce the real TDD red, confirm the test is present in source and use `mvn -f "D:/path/to/pom.xml" -Dtest=MyServiceTest test` before trusting `surefire:test`. Use `clean test` only when outputs are inconsistent or the user explicitly wants a full refresh. Surefire is primarily for unit tests; if the user is asking for integration tests or `*IT` flows, prefer Maven Failsafe instead of forcing Surefire.
