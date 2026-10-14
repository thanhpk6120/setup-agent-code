<!-- HOWTO: GUIDE FOR INITIALIZING A NEW PROJECT FROM TEMPLATE
1. Copy this file to the root directory of the new project and rename it to `AGENTS.md`.
2. Find and replace all placeholders in the form `{{PLACEHOLDER_NAME}}` with actual project information.
3. Remove all <!-- HOWTO --> comment blocks before committing.
-->

> ⚠️ **TEMPLATE:** This file is a starter template used to create `AGENTS.md` for new projects.
> Do not use this file directly as an agent guide without filling in project-specific details.

---

# AGENTS.md — Root Project Agent Guide

## 0. File metadata [REQUIRED]

```yaml
project: {{PROJECT_NAME}}
doc_version: 1.0.0
updated_at: {{YYYY-MM-DD}}
owner: {{PROJECT_OWNER}}
docs_repo: {{DOCS_GIT_REPO_URL}}
ticket_prefix: {{TICKET_PREFIX}}
language_for_ai_replies: {{English | Vietnamese}}
```

---

## 1. Project overview [REQUIRED]

**{{PROJECT_NAME}}** is {{Brief description of the system / project goal}}.

**Business goal:** {{Primary business objective of the system}}.

**Main capabilities:**
- {{Capability 1}}
- {{Capability 2}}
- {{Capability 3}}
- {{Capability 4}}

**Customer / stakeholders:** {{List of customers, end users, operations team, stakeholders}}.

**Out of scope for this workspace:** {{External systems, modules, or services outside this workspace scope}}.

---

## 2. Session start protocol [REQUIRED]

Read in this exact order **before** planning, writing code, testing, or reviewing:

1. Run `git pull` inside the `docs/` directory.
2. This file (`AGENTS.md`).
3. `docs/README.md` — spec-driven workflow process.
4. `docs/ARCHITECTURE.md` — system architecture, network ports, inter-service communications.
5. `docs/specs/<domain>.md` — business specification relevant to the task.
6. `docs/rules/<rule>.md` — working rules corresponding to the task type.
7. `docs/DESIGN.md` — if the task includes UI/UX changes.
8. `docs/features/<TICKET-ID>/` — if the task is tied to a specific ticket.

**Do not write code before completing steps 1–6.**

---

## 3. Workspace layout [REQUIRED]

<!-- HOWTO: List workspace directory structure and actual services with tech stack/ports -->
```text
{{WORKSPACE_ROOT}}/                  ← parent folder (workspace root, NOT a git repo)
├── AGENTS.md                        ← root agent instruction file
├── docs/                            ← docs repo (separate git repo) — source of truth
│   ├── README.md                    ← specification workflow
│   ├── ARCHITECTURE.md              ← system architecture overview
│   ├── DESIGN.md                    ← UI/UX design guide
│   ├── COMMANDS.md                  ← command shortcuts catalog
│   ├── specs/                       ← domain-specific business specifications
│   ├── rules/                       ← AI agent operational rules
│   ├── features/                    ← ticket tracking ({{TICKET_PREFIX}}-XXXX)
│   └── skills/                      ← domain skills
├── {{service-1-dir}}/               ← {{Tech Stack & Port / Role}}
├── {{service-2-dir}}/               ← {{Tech Stack & Port / Role}}
└── {{service-3-dir}}/               ← {{Tech Stack & Port / Role}}
```

**Naming rule [REQUIRED]:** The local directory name is the **canonical name** used across all documentation, plans, tasks, and reports. Do not refer to a service by its git repo name or README title. When conflicts arise, the **actual source code wins** and must be documented in `docs/ARCHITECTURE.md`.

---

## 4. Service registry [REQUIRED]

### 4.1 Canonical Service Tags (`{{SERVICE_TAGS}}`)
`{{service-key-1}}`, `{{service-key-2}}`, `{{service-key-3}}`

### 4.2 Service Registry Table
| service-key (canonical) | Repo path | Git repository | Role | Runtime / port | Datastore |
|---|---|---|---|---|---|
| `{{service-key-1}}` | `./{{service-key-1}}` | `{{GIT_URL_SERVICE_1}}` | {{Description of service 1 role}} | {{Runtime / Framework / Port}} | {{Datastore}} |
| `{{service-key-2}}` | `./{{service-key-2}}` | `{{GIT_URL_SERVICE_2}}` | {{Description of service 2 role}} | {{Runtime / Framework / Port}} | {{Datastore}} |
| `{{service-key-3}}` | `./{{service-key-3}}` | `{{GIT_URL_SERVICE_3}}` | {{Description of service 3 role}} | {{Runtime / Framework / Port}} | {{Datastore}} |
| `docs` | `./docs` | `{{DOCS_GIT_REPO_URL}}` | Documentation source of truth | Markdown | — |

**Shared Infrastructure:**
- Database: {{Databases, e.g., PostgreSQL, MongoDB, MySQL}}
- File / Object Storage: {{Object Storage, e.g., MinIO, AWS S3}}
- Queue / Message broker: {{Message Broker, e.g., Kafka, RabbitMQ, SQS}}
- Cache: {{Cache, e.g., Redis, Caffeine}}
- Specialized Integrations: {{Specialized, e.g., HSM, Gateway, Identity Provider}}

### 4.3 Service Resolution Rules [REQUIRED]
1. Target service must be **explicitly specified** in order of priority: `plan.md` front-matter `service:` → `Service` column in `tasks.md` → direct user instruction.
2. Absolutely do not guess services via grep/glob.
3. Only operate on files within the `Repo path` mapped from the table above.
4. If the target service is unidentified or a multi-repo task is undeclared: **STOP AND ASK**.

---

## 5. Tech stack [REQUIRED]

| Service | Framework / version | Language / version | Auth | Build & run |
|---|---|---|---|---|
| `{{service-key-1}}` | {{Framework / Version}} | {{Language / Version}} | {{Auth Mechanism}} | `{{BUILD_CMD}}` / `{{RUN_CMD}}` |
| `{{service-key-2}}` | {{Framework / Version}} | {{Language / Version}} | {{Auth Mechanism}} | `{{BUILD_CMD}}` / `{{RUN_CMD}}` |
| `{{service-key-3}}` | {{Framework / Version}} | {{Language / Version}} | {{Auth Mechanism}} | `{{BUILD_CMD}}` / `{{RUN_CMD}}` |

---

## 6. Source-of-truth map [REQUIRED]

| Topic to find / change | Document to read first |
|---|---|
| Architecture, services, external integrations | `docs/ARCHITECTURE.md` |
| Detailed business specification for domain A | `docs/specs/{{domain-a}}.md` |
| Detailed business specification for domain B | `docs/specs/{{domain-b}}.md` |
| Interface, UI components, theme | `docs/DESIGN.md` |
| Specific ticket or feature | `docs/features/<TICKET-ID>/` |
| Agent operational rules | `docs/rules/*.md` |
| Agent skill execution instructions | `docs/skills/<skill-name>/SKILL.md` |

---

## 7. Business domain map

| # | Domain | Backend module / service | Frontend feature | Spec file |
|---|---|---|---|---|
| 1 | {{Business Domain 1}} | `{{backend-service-1}}` | `{{frontend-service-1}}` | `docs/specs/{{domain-1}}.md` |
| 2 | {{Business Domain 2}} | `{{backend-service-2}}` | `{{frontend-service-2}}` | `docs/specs/{{domain-2}}.md` |
| 3 | {{Business Domain 3}} | `{{backend-service-3}}` | `{{frontend-service-3}}` | `docs/specs/{{domain-3}}.md` |

---

## 8. Feature workflow [REQUIRED]

### 8.1 Feature folder model

Each work item is managed at `docs/features/<TICKET-ID>/` (e.g. `{{TICKET_PREFIX}}-1024/`):

| File | Owner | Content |
|---|---|---|
| `expect.md` | BA | Business requirements, actors, acceptance criteria, out-of-scope |
| `plan.md` | DEV + AI | Technical design; must pass Gate 1 review before coding |
| `tasks.md` | DEV + AI | Task checklist organized by service, with `Service` column and status |
| `testcase.md` | AI | Test scenarios generated from `expect.md` |
| `impact.md` | AI + DEV | Blast radius, risks, safety checklist |
| `report.md` | AI | Actual modified files and actual test results |
| `deploy.md` | DEV | Configuration/DB/deployment guide if infrastructure changes exist |

### 8.2 Lifecycle and gates

```text
draft ──► plan-review ──► approved ──► in_progress ──► testing ──► done
                                              │
                                              └──► blocked / cancelled
```

- **Gate 1 — Plan review:** `plan.md` must be self-verified by DEV and approved by TechLead before coding.
- **Gate 2 — Docs update review:** Changes to `docs/specs/` and `docs/ARCHITECTURE.md` must be approved by TechLead before merging.

### 8.3 Front matter for tasks.md

```md
---
feature: {{TICKET_PREFIX}}-0000
service: {{service-key}}
status: in_progress
owner: AI
updated_at: {{YYYY-MM-DD}}
---
```

---

## 9. Rule index [REQUIRED]

| Rule file | When to run | Input | Output |
|---|---|---|---|
| `docs/rules/init-docs.md` | Initializing or re-syncing full documentation | Source code across all services | `ARCHITECTURE.md`, `DESIGN.md`, `specs/*.md` |
| `docs/rules/create-plan.md` | When `expect.md` is available | `expect.md` + base docs | `plan.md`, `tasks.md` |
| `docs/rules/implement-task.md` | Plan approved (Gate 1) | `tasks.md` | Code + `report.md` + `deploy.md` + docs diff |
| `docs/rules/create-testcase.md` | After plan, before coding | `expect.md` | `testcase.md` |

---

## 10. Service quick rules [REQUIRED]

### 10.1 Layer Read Order (`{{LAYER_READ_ORDER}}`)
<!-- HOWTO: Declare code reading order for each framework/techstack in the project -->
- **Spring Boot (Java):** `controller` / `grpc` → `service` → `repository`/`dao` → `entity`/`model` → `dto` → `config`
- **Node.js / Express / NestJS:** `controller` / `resolver` → `service` → `repository` / `entity` → `dto` / `interface` → `config`
- **React (TypeScript/JavaScript):** `router` → `view`/`page` → `component` → `store`/`slice`/`thunk` → `api service`
- **Angular (TypeScript):** `routing-module` → `page`/`component` → `service` → `model`
- **Vue (TypeScript/JavaScript):** `router` → `views`/`pages` → `components` → `stores`/`pinia` → `api`

### 10.2 Service Quick Matrix & Verification Commands (`{{VERIFY_COMMANDS}}`)

| Service | Source Code Read Order (`{{LAYER_READ_ORDER}}`) | Verification Command (`{{VERIFY_COMMANDS}}`) | Technical Constraints |
|---|---|---|---|
| `{{service-key-1}}` | `{{controller}}` → `{{service}}` → `{{repository}}` → `{{model}}` → `{{config}}` | `{{mvn clean test / npm test}}` | {{Architectural constraints, security, no business logic in controllers}} |
| `{{service-key-2}}` | `{{router}}` → `{{views}}` → `{{components}}` → `{{store}}` → `{{api}}` | `{{npm run build / npm test}}` | {{UI/UX standards, mandatory state/error handling}} |
| `{{service-key-3}}` | `{{grpc/service}}` → `{{worker}}` → `{{client}}` → `{{config}}` | `{{mvn clean test / pytest / go test}}` | {{Performance constraints, timeouts, transactions}} |

### 10.3 Deploy & release commands (`{{DEPLOY_COMMANDS}}`)

| Service | Build artifact / Image | Deploy script / Command | Rollback | CI/CD Status |
|---|---|---|---|---|
| `{{service-key-1}}` | `{{BUILD_PACKAGE_CMD}}` | `{{DEPLOY_SCRIPT_OR_K8S}}` | `{{ROLLBACK_CMD}}` | {{CI/CD status, e.g.: GitLab CI / Jenkins / K8s}} |
| `{{service-key-2}}` | `{{BUILD_PACKAGE_CMD}}` | `{{DEPLOY_SCRIPT_OR_K8S}}` | `{{ROLLBACK_CMD}}` | {{CI/CD status}} |
| `{{service-key-3}}` | `{{BUILD_PACKAGE_CMD}}` | `{{DEPLOY_SCRIPT_OR_K8S}}` | `{{ROLLBACK_CMD}}` | {{CI/CD status}} |

*Note:* See detailed command catalog at `docs/COMMANDS.md`.

---

## 11. Agent working rules [REQUIRED]

### 11.1 Project Configuration Defaults
- **DB docs path (`{{DB_DOCS_PATH}}`):** `docs/database/` (if present, snapshots, Liquibase/Flyway/SQL migrations in respective repo).
- **Impact tool (`{{IMPACT_TOOL}}`):** `none` (or impact tool name if present; defaults to git diff and source tracing per `{{LAYER_READ_ORDER}}`).
- **I18N requirement (`{{I18N_REQUIRED}}`):** `{{false | true}}` (default primary language, only `true` if multi-language is strictly required).
- **Integration surfaces (`{{INTEGRATION_SURFACES}}`):**
  - {{RPC/Protobuf interfaces, e.g.: gRPC Protobuf contracts at `*/src/main/resources/proto/*.proto`}}
  - {{REST APIs, e.g.: REST API endpoints / OpenAPI specs}}
  - {{Message Broker events / topic schemas}}
  - {{External integrations / Third-party protocols}}
- **Status vocabulary (`{{STATUS_VOCABULARY}}`):** `draft` → `plan-review` → `approved` → `in_progress` → `testing` → `done` (`blocked` / `cancelled`)
- **Task format (`{{TASK_FORMAT}}`):** `checklist`

### 11.2 Scope and Safety
- Do not implement any feature outside the scope approved in `expect.md` / `plan.md` / `tasks.md`.
- Keep task status in `tasks.md` continuously updated during execution.
- `report.md` must reflect actual modified files and actual test results (`{{REPORT_EVIDENCE}}`).
- Never commit or record secrets, API keys, passwords, or certificate private keys into code or documentation.
- Do not edit build artifact directories (`dist/`, `target/`, `node_modules/`, `build/`).
- **Dependency policy (`{{DEPENDENCY_POLICY}}`):** {{Policy for adding dependencies, e.g.: Do not add new dependencies without Gate 1 approval}}.
- **Forbidden changes (`{{FORBIDDEN_CHANGES}}`):** {{Changes that require stopping for re-approval, e.g.: Changing public API/Protobuf contracts, DB schema, RBAC/Security}}.
- **Deploy triggers (`{{DEPLOY_TRIGGERS}}`):** {{Changes requiring deploy.md, e.g.: DB migration, config/env changes, new dependencies, scheduled jobs, contracts}}.
- **Mockable integrations (`{{MOCKABLE_INTEGRATIONS}}`):** {{List of services allowed to be mocked locally, e.g.: Gateway, Payment, Third-party APIs}}.

### 11.3 Code Standards (`{{CODE_STYLE_RULES}}`)
- Follow layered architecture: Controller/Handler → Service/Business Engine → Repository/Client Adapter.
- File implementation order in tasks (`{{IMPLEMENT_ORDER}}`):
  - Backend: Entity/Migration/DTO → Repository → Service → Controller/gRPC Handler → Config/Test
  - Frontend: Types/Models → API Service → Store/State → Components → Pages/Routes
- Do not place business logic in Controller/View layers.
- All newly created files must use **UTF-8 without BOM** encoding.
- Code comments and responses in **{{English | Vietnamese}}**.

### 11.4 Common impact zones (`{{COMMON_IMPACT_ZONES}}`)

| Change (Change X) | Affects (Affects Y) | Risk Level | Required Action |
|---|---|---|---|
| {{Public API/Protobuf/RPC changes}} | {{All dependent clients and services}} | **HIGH** | {{Synchronously update client SDKs/contracts, verify backward compatibility}} |
| {{Core data schema changes}} | {{Reporting, primary transaction flows}} | **HIGH** | {{Create migration scripts, assess legacy data}} |
| {{Auth/security configuration changes}} | {{User login and authentication flows}} | **HIGH** | {{Thoroughly test authorization scenarios and token handling}} |

---

## 12. Project skills [OPTIONAL]

| Scenario | Skill (`docs/skills/`) |
|---|---|
| Initialize or refresh full system documentation | `docs/skills/init-docs/SKILL.md` |
| Create technical plan for a new ticket | `docs/skills/create-plan/SKILL.md` |
| Execute task checklist and write source code | `docs/skills/implement-task/SKILL.md` |
| Generate test scenarios from requirements | `docs/skills/create-testcase/SKILL.md` |

---

## 13. Git rules [REQUIRED] (`{{BRANCH_RULE}}`, `{{COMMIT_RULE}}`)

### 13.1 Branch convention (`{{BRANCH_RULE}}`)
- Branch naming: `feature/{{TICKET_PREFIX}}-<TICKET-NUMBER>-<slug>` or `feature/{{TICKET_PREFIX}}-<TICKET-NUMBER>` (e.g.: `feature/{{TICKET_PREFIX}}-1024-user-auth` or `feature/{{TICKET_PREFIX}}-1024`) — **consistent across all participating repositories**.
- Check branch before starting work: `git status`.
- Never switch branches when the working tree is dirty (uncommitted/unstashed changes).

### 13.2 Commit & Push (`{{COMMIT_RULE}}`)
1. `git status` to inspect changes.
2. Check `git diff` and `git diff --staged`.
3. Format commit message: `<TICKET-ID>: <concise description>` (e.g.: `{{TICKET_PREFIX}}-1024: add redis caching layer`).
4. `git push origin <current-branch>`.
5. **Agent must not commit, push, or merge unless explicitly requested.**

---

## 14. Do not modify unless explicitly requested [REQUIRED]

- `node_modules/`, `target/`, `build/`, `dist/`, `.idea/`, `.vscode/`
- `.env*`, keystores (`.jks`, `.p12`), certificates, private keys, secrets, credentials
- Log files, caches, database dump files outside `docs/database/`

---

## 15. Quick links [REQUIRED]

> **Note:** The links below are relative paths from the root directory of the project after copying this file to root (`AGENTS.md`).

- [docs/README.md](docs/README.md) — Documentation overview
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — System architecture
- [docs/DESIGN.md](docs/DESIGN.md) — UI/UX design guide
- [docs/COMMANDS.md](docs/COMMANDS.md) — Command shortcuts catalog
- [docs/specs/](docs/specs/) — Business specifications
- [docs/rules/](docs/rules/) — Operational rules
- [docs/features/](docs/features/) — Ticket/feature tracking
- [docs/skills/](docs/skills/) — Skill catalog
