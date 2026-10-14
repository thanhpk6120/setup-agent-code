---
name: dotnet-impact-unittest-loop
description: 'Analyze impact scope, auto-generate xUnit/Moq (or NSubstitute) test cases, and loop until 90% coverage for .NET source code.'
---

# .NET Impact Unittest Loop

Use this skill after .NET (C#) source changes are complete and the user requests a retest, an impact assessment, or higher coverage.

## 1. Analyze impact scope (Impact)

Use `git status` or `git diff` to identify changed `.cs` files.
Map diff changes to specific methods:
- Use `git diff -U0` or `git diff -W` to read hunk headers containing the changed C# method names.
- If GitNexus MCP is available, run `impact/context/trace` to scan the dependency graph.
- For manual analysis, follow the Clean Architecture / N-Tier layers: `Controller/Endpoints -> Application/Service -> Domain/Entities -> Infrastructure/Repository`.
Build an impact assessment table: File / Function / Corresponding API / Risk level (HIGH/MED/LOW).

## 2. Determine test targets (Target)

Specify the exact functions and APIs to test, following these rules:
- Include directly changed functions (Direct changes).
- Include callers or callees of the changed function within 1 hop.
- Include API endpoints/handlers directly related to the changed logic flow.
- Exclude boilerplate, plain DTOs, migrations, and DI configuration (`Program.cs`, `Startup.cs`).

## 3. Create tests

Write tests with **xUnit** plus **Moq** (or **NSubstitute**).
Place test files in the matching test project (e.g. `tests/{Project}.UnitTests`) mirroring the source project namespace. Test file suffix is `Tests.cs`.
Every affected method must cover these logic branches:
- `[Fact]`: happy path, null/empty values, thrown exceptions (`Assert.ThrowsAsync<T>`).
- `[Theory]` + `[InlineData]` / `[MemberData]`: boundary tests and varied parameter sets.
- Mock system boundaries: DbContext, HttpClient, external services via interfaces.

## 4. Run selective tests

Never run the full test suite unless the impact spans the whole system.
Run selective tests with `--filter FullyQualifiedName`:
```bash
dotnet test --filter "FullyQualifiedName~{Namespace}.{TestClassName}" --collect "XPlat Code Coverage"
```
Coverlet auto-generates the default report at `TestResults/{guid}/coverage.cobertura.xml`.

## 5. Coverage improvement loop (Loop-until-90)

1. **Read per-method coverage**:
   Read `line-rate` and `branch-rate` directly from the `<method>` tag in `coverage.cobertura.xml`.
2. **Generate an HTML report for visual inspection when needed**:
   Use ReportGenerator to export the report:
   `reportgenerator -reports:"**/coverage.cobertura.xml" -targetdir:"coveragereport" -reporttypes:Html`
3. **Done criteria**:
   Both `line-rate` and `branch-rate` of the affected method reach >= 0.90 (90%).
4. **Loop (max 5 iterations)**:
   If below 90%, inspect lines/branches with `hits="0"`, add matching test cases, then rerun the selective test.
   Log each iteration: sequence number / line & branch coverage % / missing branch.

## 6. Stop and ask

Stop the loop and ask the user when any of these holds:
- A critical business-logic bug is found that could break API contracts or data flow.
- The code is untestable by design (Untestable: static state, missing interfaces, constructors directly newing up external dependencies).
- Coverage does not increase for 2 consecutive iterations.
Present the file, method, cause, and proposed options clearly.

## 7. Package results (Final Artifact)

When the loop ends (90% reached or forced stop per step 6), archive the HTML report directory exactly once. The resulting ZIP must be saved at: `evidence/dotnet-final-coverage.zip`.
Never create a ZIP after each iteration.

## Output

```markdown
# .NET Impact Test Loop Result

## Impact analysis table
| File | Function | API | Risk level (HIGH/MED/LOW) |
|------|-----|-----|------------------------------|

## Retest list
- Class.Method1 (Selection reason)
- Class.Method2 (Selection reason)

## Coverage results (Coverlet/Cobertura)
- Method: Namespace.Class.Method
  - Line Coverage: X%
  - Branch Coverage: Y%

## Iteration log
- Iteration 1: X% line / Y% branch. Missing: ArgumentNullException check branch.
- Iteration 2: 95% line / 92% branch. Added Theory for empty-value tests.

## Evidence
- Archived evidence: evidence/dotnet-final-coverage.zip
```

## Safety boundaries

- Do not modify source code in the main project (`src/`) during the test loop.
- Do not lower the required coverage threshold (90%).
- Do not delete or disable (`[Fact(Skip="...")]`) old test cases to fake coverage.
- Do not commit or push source code unless requested.
