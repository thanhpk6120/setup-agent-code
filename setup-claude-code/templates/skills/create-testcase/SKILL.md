---
name: create-testcase
description: Use when the user asks to create, draft, review, or update testcase.md for a docs/features ticket from expect.md, acceptance criteria, or the Spec-Driven workflow.
---

# Rule 03 — Create Testcase

> **Audience:** AI agent. Follow the steps in order. Do not skip a step and do not invent a step.
> **Goal:** Create `testcase.md` from `expect.md` to verify features against acceptance criteria, prior to or alongside implementation.
> **Scope of this file:** this rule is **project-agnostic**. It must work unchanged for every project in the company.
> **Predecessor:** `docs/features/<TICKET-ID>/expect.md` (or `docs/rules/create-plan.md`).

---

## 0. Project configuration contract [READ THIS FIRST]

This rule contains **no project-specific hardcoded values**. All project configuration is defined in a single source of truth:

| File | What it provides |
|---|---|
| `{{PROJECT_ROOT}}/AGENTS.md` | Project overview, **service registry** (§4), tech stack (§5), quick rules & read order & verify commands (§10), agent working rules & integration surfaces (§11), git rules (§13), do-not-touch list (§14) |

### Configuration keys resolved directly from `AGENTS.md`

The rule references these by name. Each `{{key}}` used in this file resolves from `AGENTS.md`:

| Key | Location in `AGENTS.md` | Meaning |
|---|---|---|
| `{{SERVICE_TAGS}}` | §4.1 | Canonical service tag list, used when a test case must name the service under test |
| `{{IMPACT_TOOL}}` | §11.1 | Code-index / impact tool used to discover regression flows (`none` if unused) |
| `{{STATUS_VOCABULARY}}` | §11.1 | Allowed status values, used to mark a test case `blocked` or `draft` |
| `{{EXTRA_RULES}}` | §9 | Companion rules to read when relevant (`init-docs`, `create-plan`, `implement-task`) |

---

## 1. When to run

- After BA produces `docs/features/<TICKET-ID>/expect.md`.
- Recommended to run after `create-plan.md` to reference the technical plan, but test cases must still treat `expect.md` as primary source.

## 2. Stopping criteria — verify before writing anything

STOP and ask the user if any of the following holds true:

1. `docs/features/<TICKET-ID>/expect.md` does not exist.
2. `expect.md` is missing acceptance criteria or missing primary actors.
3. Cannot determine the expected result for an acceptance criterion — record under `Open Questions`, never guess.

---

## 3. Inputs and outputs

### Inputs

| Input | Source | Required |
|---|---|---|
| `docs/features/<TICKET-ID>/expect.md` | BA | **Yes** — primary source |
| `docs/features/<TICKET-ID>/plan.md` | Rule 01 | If available — technical scope reference |
| `docs/specs/<domain>.md` | docs | **Yes** for all relevant domains |
| `docs/DESIGN.md` | docs | When feature includes UI |
| `{{EXTRA_RULES}}` | docs | When trigger conditions for companion rule apply |

### Outputs

| Output | Description |
|---|---|
| `docs/features/<TICKET-ID>/testcase.md` | Test suite covering acceptance criteria, following template in Step 2 |

> **Output location is mandatory.** File must be written inside `docs/features/<TICKET-ID>/` in the docs repo. If lacking write permissions to that path, **request permission** — do not write elsewhere.

---

## 4. Procedure

### Step 0 — Mandatory Pre-requisites Before Writing Test Cases

- Run `git pull` inside `docs/`.
- Read `expect.md` first.
- Only use `plan.md` to understand technical scope; do not create test cases for implementation details unless specified in acceptance criteria.

If `expect.md` is missing acceptance criteria or primary actors:
- Stop and ask BA/DEV.

### Step 1 — Extract Test Requirements

From `expect.md`, identify:
- actor/user role,
- preconditions,
- primary inputs,
- user action or API call,
- expected result,
- out-of-scope non-tested items,
- special test data to prepare.

If `{{IMPACT_TOOL}}` is not `none` and has an index for the relevant service, use it to identify regression flows. With GitNexus: `mcp__gitnexus__query` for execution flows, `mcp__gitnexus__context` on key symbols/APIs for callers/callees, and `mcp__gitnexus__route_map` when identifying API handlers/consumers. Use results to augment regression flows, not to replace Acceptance Criteria in `expect.md`.

### Step 2 — Write Behavioral Test Cases

Minimum structure:

```md
# <TICKET-ID> — Testcase

## Scope

## Test Data

## Test Cases

| ID | Scenario | Preconditions | Steps | Expected Result | Priority |
|---|---|---|---|---|---|

## Non-Functional Checks

## Out of Scope

## Open Questions
```

Rules:
- Every acceptance criterion must have at least one testcase.
- Test cases must describe observable behavior, not internal function/class names.
- UI test cases must have explicit user steps.
- API test cases must define expected request/response at business level, without fabricating endpoints if not yet defined.

### Step 3 — Cover Error Flows and Boundaries

Create test cases for:
- happy path,
- missing/invalid inputs,
- insufficient permissions if RBAC applies,
- empty data,
- pre-existing/duplicate states if business logic permits.

Do not create fabricated test cases for scenarios outside scope.

### Step 4 — Link Test Cases to Acceptance Criteria

- If `expect.md` defines AC identifiers, use them in the test cases.
- If lacking AC identifiers, number `AC1`, `AC2`, ... in order of appearance in `expect.md` and document the mapping.

Example:

```md
## Acceptance Criteria Mapping

| AC | Test Cases |
|---|---|
| AC1 | TC-001, TC-002 |
```

### Step 5 — Open Questions

If expected results cannot be determined:
- Never guess.
- Record under `Open Questions`.
- Mark associated test cases as `blocked` or `draft` per `{{STATUS_VOCABULARY}}`.

---

## 5. Stopping criteria

- Stop after generating `docs/features/<TICKET-ID>/testcase.md`.
- Do not write code in this rule.
- Do not modify `plan.md` unless explicitly requested by DEV.
- Do not claim test cases complete while open questions affecting acceptance criteria remain.

> `testcase.md` is consumed by Rule 02 (`implement-task.md`) at Step 4 and verified at Step 8. All scoped test cases must pass, or have explicit explanations in `report.md`, before proposing docs diff for Gate 2.

---

## 6. Project customization

All project configurations live in:

👉 **`AGENTS.md`** at the project root (service registry, tech stack, quick rules, agent working rules, git rules).

The agent **must read `AGENTS.md` together with this rule** and follow the values defined in it.
