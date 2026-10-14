---
name: dotnet-impact-unittest-loop
description: 'Analyze impact scope, automatically generate xUnit/Moq (or NSubstitute) test cases, and run in a loop to achieve 90% coverage on .NET code.'
---

# .NET Impact Unittest Loop

Use this skill after .NET (C#) code changes are completed and the user requests retesting, impact evaluation, or increasing test coverage.

## 1. Analyze Impact Scope

Use `git status` or `git diff` to identify modified `.cs` files.
Map diff changes to specific methods:
- Use `git diff -U0` or `git diff -W` to inspect hunk headers containing modified C# method names.
- If GitNexus MCP is available, use `impact/context/trace` to inspect dependency graphs.
- For manual analysis, follow Clean Architecture / N-Tier layers: `Controller/Endpoints -> Application/Service -> Domain/Entities -> Infrastructure/Repository`.
Build an impact assessment table: File / Function / Corresponding API / Risk Level (HIGH/MED/LOW).

## 2. Identify Target Scope

Specify concrete functions and APIs requiring tests based on the following rules:
- Include directly changed functions (Direct changes).
- Include callers or callees of the changed function within a 1-hop distance.
- Include API Endpoints/Handlers directly related to the modified logic flow.
- Exclude boilerplate, pure DTOs, migrations, and DI configurations (`Program.cs`, `Startup.cs`).

## 3. Generate Tests

Write tests using **xUnit** combined with **Moq** (or **NSubstitute**).
Place test files in the corresponding test project (e.g. `tests/{Project}.UnitTests`) mirroring the namespace of the source project. Test file suffix must be `Tests.cs`.
Every affected method must cover the following logic branches:
- `[Fact]`: Happy path, null/empty values, thrown exceptions (`Assert.ThrowsAsync<T>`).
- `[Theory]` + `[InlineData]` / `[MemberData]`: Boundary testing and varying parameter sets.
- Mock system boundaries: DbContext, HttpClient, external services via Interfaces.

## 4. Run Selective Tests

Running the full test suite is forbidden unless impact spreads system-wide.
Run selective tests using `--filter FullyQualifiedName`:
```bash
dotnet test --filter "FullyQualifiedName~{Namespace}.{TestClassName}" --collect "XPlat Code Coverage"
```
Coverlet automatically outputs reports by default to `TestResults/{guid}/coverage.cobertura.xml`.

## 5. Coverage Evaluation Loop (Loop-until-90)

1. **Read coverage by method**:
   Retrieve `line-rate` and `branch-rate` directly from the `<method>` element in `coverage.cobertura.xml`.
2. **Generate HTML report when visual detail is needed**:
   Use ReportGenerator to export reports:
   `reportgenerator -reports:"**/coverage.cobertura.xml" -targetdir:"coveragereport" -reporttypes:Html`
3. **Passing criteria**:
   Both `line-rate` and `branch-rate` of the affected method must reach >= 0.90 (90%).
4. **Loop (maximum 5 iterations)**:
   If below 90%, inspect lines/branches with `hits="0"`, add corresponding test cases, and re-run selective tests.
   Log each iteration: Iteration number / % line & branch coverage / Missing branches.

## 6. Stop and Ask

Stop the loop and ask the user if any of the following stopping conditions occur:
- Critical business logic flaw discovered that may break API contracts or data flow.
- Code is untestable by design (static state, missing interfaces, constructor directly instantiating external dependencies).
- Coverage does not increase across 2 consecutive iterations.
Clearly present file, method, cause, and proposed solutions.

## 7. Package Final Artifact

When the loop concludes (reaches 90% or stops per step 6), compress the HTML report directory once. The resulting ZIP file must be saved at: `evidence/dotnet-final-coverage.zip`.
DO NOT create ZIP files after every iteration.

## Output

```markdown
# .NET Impact Test Loop Result

## Impact Table
| File | Method | API | Risk Level (HIGH/MED/LOW) |
|------|--------|-----|---------------------------|

## Retest List
- Class.Method1 (Selection rationale)
- Class.Method2 (Selection rationale)

## Coverage Result (Coverlet/Cobertura result)
- Method: Namespace.Class.Method
  - Line Coverage: X%
  - Branch Coverage: Y%

## Iteration Log
- Loop 1: Reached X% line / Y% branch. Missing: ArgumentNullException branch.
- Loop 2: Reached 95% line / 92% branch. Added Theory testing empty values.

## Evidence
- Archive: evidence/dotnet-final-coverage.zip
```

## Safety Boundaries

- Do not edit source code in the main project (`src/`) during test loops.
- Do not lower the required coverage threshold (90%).
- Do not delete or disable (`[Fact(Skip="...")]`) existing test cases to artificially boost coverage.
- Do not commit or push source code unless requested.
