---
name: create-testcase
description: Use when the user asks to create, draft, review, or update testcase.md for a docs/features ticket from expect.md, acceptance criteria, or the Spec-Driven workflow.
---

# Rule 03 — Create Testcase

> **Audience:** AI agent. Follow the steps in order. Do not skip a step and do not invent a step.
> **Goal:** Create `testcase.md` from `expect.md` to verify the feature against acceptance criteria, before or in parallel with implementation.
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

- After the BA has `docs/features/<TICKET-ID>/expect.md`.
- Prefer running after `create-plan.md` for plan context, but test cases must still follow `expect.md` as the primary source.

## 2. Stop conditions — check before writing anything

STOP and ask the user if any of the following is true:

1. `docs/features/<TICKET-ID>/expect.md` does not exist.
2. `expect.md` lacks acceptance criteria or a primary actor.
3. The expected result for some acceptance criterion cannot be determined — record it in `Open Questions`, do not guess.

---

## 3. Inputs and outputs

### Inputs

| Input | Source | Required |
|---|---|---|
| `docs/features/<TICKET-ID>/expect.md` | BA | **Yes** — primary source |
| `docs/features/<TICKET-ID>/plan.md` | Rule 01 | If present — technical scope reference |
| `docs/specs/<domain>.md` | docs | **Yes** for every related domain |
| `docs/DESIGN.md` | docs | When the feature has UI |
| `{{EXTRA_RULES}}` | docs | When that rule's trigger condition applies |

### Outputs

| Output | Description |
|---|---|
| `docs/features/<TICKET-ID>/testcase.md` | Test cases following acceptance criteria, per the Step 2 template |

> **Output location is mandatory.** The file must be written under `docs/features/<TICKET-ID>/` in the docs repo. If write access to that exact path is missing, **ask for permission** — never write elsewhere.

---

## 4. Procedure

### Step 0 — Required before writing test cases

- Run `git pull` in `docs/`.
- Read `expect.md` first.
- Use `plan.md` only to understand technical scope; do not create test cases for implementation details absent from the acceptance criteria.

If `expect.md` lacks acceptance criteria or a primary actor:
- Stop and ask the BA/DEV.

### Step 1 — Extract test requirements

From `expect.md`, identify:
- actor/user role,
- precondition,
- primary inputs,
- user actions or API calls,
- expected result,
- out-of-scope items needing no test,
- special data to prepare.

If `{{IMPACT_TOOL}}` is not `none` and indexes the related service, use it to find regression flows. With GitNexus: `mcp__gitnexus__query` to find related execution flows, `mcp__gitnexus__context` on key symbols/APIs for callers/callees, and `mcp__gitnexus__route_map` when the test case must pin down API handlers/consumers. Use these results to add regression flows to test, never to replace the Acceptance Criteria in `expect.md`.

### Step 2 — Write behavior-based test cases

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
- Every acceptance criterion must have at least one test case.
- Test cases must describe observable behavior, not internal function/class names.
- UI test cases must have clear user steps.
- API test cases must state expected request/response at business level; do not invent endpoints when the plan/docs have not defined them.

### Step 3 — Cover error and boundary flows

Create test cases for:
- happy path,
- missing/invalid inputs,
- insufficient permissions when the feature has authorization,
- empty data,
- already-exists/duplicate states when the business flow allows them.

Do not fabricate test cases for out-of-scope situations.

### Step 4 — Link test cases to acceptance criteria

- If `expect.md` has AC codes, use them in the test cases.
- Without AC codes, number them `AC1`, `AC2`, ... in `expect.md` order and record the mapping explicitly.

Example:

```md
## Acceptance Criteria Mapping

| AC | Test Cases |
|---|---|
| AC1 | TC-001, TC-002 |
```

### Step 5 — Open questions

When the expected result cannot be determined:
- Do not guess.
- Record it in `Open Questions`.
- Mark the related test case `blocked` or `draft` per `{{STATUS_VOCABULARY}}`.

---

## 5. Stop criteria

- Stop after creating `docs/features/<TICKET-ID>/testcase.md`.
- No coding in this rule.
- Do not edit `plan.md` unless DEV explicitly requests it.
- Do not claim test cases are complete while `Open Questions` affecting acceptance criteria remain.

> `testcase.md` is read by Rule 02 (`implement-task.md`) at Step 4 and verified at Step 8. Every in-scope test case must pass, or carry a documented reason in `report.md`, before proposing the docs diff for Gate 2.

---

## 6. Project customization

All project configurations live in:

👉 **`AGENTS.md`** at the project root (service registry, tech stack, quick rules, agent working rules, git rules).

The agent **must read `AGENTS.md` together with this rule** and follow the values defined in it.
