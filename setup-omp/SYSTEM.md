<!-- HOWTO: HƯỚNG DẪN KHỞI TẠO DỰ ÁN MỚI TỪ TEMPLATE
1. Copy file này ra thư mục gốc của dự án mới và đổi tên thành `AGENTS.md`.
2. Tìm và thay thế tất cả các placeholder dạng `{{PLACEHOLDER_NAME}}` bằng thông tin thực tế của dự án.
3. Xóa bỏ toàn bộ các block comment <!-- HOWTO --> này trước khi commit.
-->

> ⚠️ **TEMPLATE / BẢN MẪU:** File này là tài liệu mẫu dùng để tạo `AGENTS.md` cho các dự án mới.
> Không sử dụng trực tiếp file này làm hướng dẫn agent khi chưa điền thông tin cụ thể.

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
language_for_ai_replies: {{Vietnamese | English}}
```

---

## 1. Project overview [REQUIRED]

**{{PROJECT_NAME}}** là {{Mô tả ngắn gọn về hệ thống / mục tiêu dự án}}.

**Business goal:** {{Mục tiêu kinh doanh chính của hệ thống}}.

**Main capabilities:**
- {{Năng lực 1}}
- {{Năng lực 2}}
- {{Năng lực 3}}
- {{Năng lực 4}}

**Customer / stakeholders:** {{Danh sách khách hàng, người dùng cuối, đội ngũ vận hành, bên liên quan}}.

**Out of scope for this workspace:** {{Những hệ thống, module hoặc dịch vụ bên ngoài nằm ngoài phạm vi workspace này}}.

---

## 2. Session start protocol [REQUIRED]

Đọc theo đúng thứ tự này **trước khi** lập kế hoạch, viết code, kiểm thử hoặc review:

1. Chạy `git pull` bên trong thư mục `docs/`.
2. File này (`AGENTS.md`).
3. `docs/README.md` — quy trình spec-driven workflow.
4. `docs/ARCHITECTURE.md` — kiến trúc hệ thống, cổng mạng, giao tiếp liên service.
5. `docs/specs/<domain>.md` — đặc tả nghiệp vụ liên quan đến task.
6. `docs/rules/<rule>.md` — quy tắc làm việc tương ứng với loại task.
7. `docs/DESIGN.md` — nếu task có thay đổi UI/UX.
8. `docs/features/<TICKET-ID>/` — nếu task gắn với ticket cụ thể.

**Không viết code trước khi hoàn thành các bước 1–6.**

---

## 3. Workspace layout [REQUIRED]

<!-- HOWTO: Liệt kê cấu trúc thư mục workspace và các service thực tế kèm công nghệ/port -->
```text
{{WORKSPACE_ROOT}}/                  ← parent folder (workspace root, NOT a git repo)
├── AGENTS.md                        ← file hướng dẫn agent gốc
├── docs/                            ← docs repo (git riêng) — nguồn chân lý (source of truth)
│   ├── README.md                    ← workflow đặc tả
│   ├── ARCHITECTURE.md              ← kiến trúc tổng thể
│   ├── DESIGN.md                    ← thiết kế UI/UX
│   ├── COMMANDS.md                  ← catalog lệnh tắt
│   ├── specs/                       ← đặc tả nghiệp vụ từng domain
│   ├── rules/                       ← quy tắc vận hành AI agent
│   ├── features/                    ← theo dõi theo ticket ({{TICKET_PREFIX}}-XXXX)
│   └── skills/                      ← domain skills
├── {{service-1-dir}}/               ← {{Tech Stack & Port / Role}}
├── {{service-2-dir}}/               ← {{Tech Stack & Port / Role}}
└── {{service-3-dir}}/               ← {{Tech Stack & Port / Role}}
```

**Naming rule [REQUIRED]:** Tên thư mục cục bộ là **tên canonical** dùng xuyên suốt trong tài liệu, plan, task và report. Không gọi service bằng tên git repo hay title trong README. Khi có xung đột, **mã nguồn thực tế thắng** và phải ghi nhận vào `docs/ARCHITECTURE.md`.

---

## 4. Service registry [REQUIRED]

### 4.1 Canonical Service Tags (`{{SERVICE_TAGS}}`)
`{{service-key-1}}`, `{{service-key-2}}`, `{{service-key-3}}`

### 4.2 Service Registry Table
| service-key (canonical) | Repo path | Git repository | Role | Runtime / port | Datastore |
|---|---|---|---|---|---|
| `{{service-key-1}}` | `./{{service-key-1}}` | `{{GIT_URL_SERVICE_1}}` | {{Mô tả vai trò service 1}} | {{Runtime / Framework / Port}} | {{Datastore}} |
| `{{service-key-2}}` | `./{{service-key-2}}` | `{{GIT_URL_SERVICE_2}}` | {{Mô tả vai trò service 2}} | {{Runtime / Framework / Port}} | {{Datastore}} |
| `{{service-key-3}}` | `./{{service-key-3}}` | `{{GIT_URL_SERVICE_3}}` | {{Mô tả vai trò service 3}} | {{Runtime / Framework / Port}} | {{Datastore}} |
| `docs` | `./docs` | `{{DOCS_GIT_REPO_URL}}` | Documentation source of truth | Markdown | — |

**Hạ tầng dùng chung:**
- Cơ sở dữ liệu: {{Databases, ví dụ: PostgreSQL, MongoDB, MySQL}}
- Lưu trữ file/đối tượng: {{Object Storage, ví dụ: MinIO, AWS S3}}
- Hàng đợi / Message broker: {{Message Broker, ví dụ: Kafka, RabbitMQ, SQS}}
- Cache: {{Cache, ví dụ: Redis, Caffeine}}
- Tích hợp chuyên biệt: {{Chuyên biệt, ví dụ: HSM, Gateway, Identity Provider}}

### 4.3 Quy tắc định vị service [REQUIRED]
1. Service mục tiêu phải được **chỉ định rõ ràng** theo thứ tự ưu tiên: `plan.md` front-matter `service:` → cột `Service` trong `tasks.md` → chỉ thị trực tiếp từ người dùng.
2. Tuyệt đối không đoán service bằng grep/glob.
3. Chỉ thao tác trên các file thuộc `Repo path` được ánh xạ từ bảng trên.
4. Nếu chưa xác định được service hoặc task liên quan nhiều repo mà chưa được khai báo: **DỪNG LẠI VÀ HỎI**.

---

## 5. Tech stack [REQUIRED]

| Service | Framework / version | Language / version | Auth | Build & run |
|---|---|---|---|---|
| `{{service-key-1}}` | {{Framework / Version}} | {{Language / Version}} | {{Auth Mechanism}} | `{{BUILD_CMD}}` / `{{RUN_CMD}}` |
| `{{service-key-2}}` | {{Framework / Version}} | {{Language / Version}} | {{Auth Mechanism}} | `{{BUILD_CMD}}` / `{{RUN_CMD}}` |
| `{{service-key-3}}` | {{Framework / Version}} | {{Language / Version}} | {{Auth Mechanism}} | `{{BUILD_CMD}}` / `{{RUN_CMD}}` |

---

## 6. Source-of-truth map [REQUIRED]

| Vấn đề cần tìm / thay đổi | Tài liệu cần đọc trước |
|---|---|
| Kiến trúc, dịch vụ, tích hợp ngoại vi | `docs/ARCHITECTURE.md` |
| Đặc tả chi tiết nghiệp vụ domain A | `docs/specs/{{domain-a}}.md` |
| Đặc tả chi tiết nghiệp vụ domain B | `docs/specs/{{domain-b}}.md` |
| Giao diện, UI component, theme | `docs/DESIGN.md` |
| Ticket hoặc tính năng cụ thể | `docs/features/<TICKET-ID>/` |
| Quy tắc vận hành của Agent | `docs/rules/*.md` |
| Hướng dẫn thực thi kỹ năng Agent | `docs/skills/<skill-name>/SKILL.md` |

---

## 7. Business domain map

| # | Domain | Backend module / service | Frontend feature | Spec file |
|---|---|---|---|---|
| 1 | {{Tên nghiệp vụ 1}} | `{{backend-service-1}}` | `{{frontend-service-1}}` | `docs/specs/{{domain-1}}.md` |
| 2 | {{Tên nghiệp vụ 2}} | `{{backend-service-2}}` | `{{frontend-service-2}}` | `docs/specs/{{domain-2}}.md` |
| 3 | {{Tên nghiệp vụ 3}} | `{{backend-service-3}}` | `{{frontend-service-3}}` | `docs/specs/{{domain-3}}.md` |

---

## 8. Feature workflow [REQUIRED]

### 8.1 Feature folder model

Mỗi hạng mục công việc được quản lý tại `docs/features/<TICKET-ID>/` (ví dụ `{{TICKET_PREFIX}}-1024/`):

| File | Owner | Nội dung |
|---|---|---|
| `expect.md` | BA | Yêu cầu nghiệp vụ, actors, tiêu chí nghiệm thu (acceptance criteria), out-of-scope |
| `plan.md` | DEV + AI | Thiết kế kỹ thuật; bắt buộc duyệt Gate 1 trước khi viết code |
| `tasks.md` | DEV + AI | Danh sách checklist công việc theo service, có cột `Service` và trạng thái |
| `testcase.md` | AI | Kịch bản kiểm thử sinh từ `expect.md` |
| `impact.md` | AI + DEV | Phạm vi ảnh hưởng, rủi ro, danh sách kiểm tra an toàn |
| `report.md` | AI | Danh sách file thay đổi thực tế và kết quả kiểm thử thực tế |
| `deploy.md` | DEV | Hướng dẫn cấu hình/DB/deployment nếu có thay đổi hạ tầng |

### 8.2 Lifecycle and gates

```text
draft ──► plan-review ──► approved ──► in_progress ──► testing ──► done
                                              │
                                              └──► blocked / cancelled
```

- **Gate 1 — Plan review:** `plan.md` phải được DEV tự kiểm tra và TechLead duyệt trước khi code.
- **Gate 2 — Docs update review:** Thay đổi tại `docs/specs/` và `docs/ARCHITECTURE.md` phải được TechLead duyệt trước khi merge.

### 8.3 Front matter của tasks.md

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

| Rule file | Khi nào chạy | Input | Output |
|---|---|---|---|
| `docs/rules/init-docs.md` | Khởi tạo hoặc đồng bộ lại toàn bộ docs | Mã nguồn toàn bộ các service | `ARCHITECTURE.md`, `DESIGN.md`, `specs/*.md` |
| `docs/rules/create-plan.md` | Đã có `expect.md` | `expect.md` + base docs | `plan.md`, `tasks.md` |
| `docs/rules/implement-task.md` | Plan đã duyệt (Gate 1) | `tasks.md` | Code + `report.md` + `deploy.md` + docs diff |
| `docs/rules/create-testcase.md` | Sau plan, trước khi code | `expect.md` | `testcase.md` |

---

## 10. Service quick rules [REQUIRED]

### 10.1 Layer Read Order (`{{LAYER_READ_ORDER}}`)
<!-- HOWTO: Khai báo thứ tự đọc code theo từng loại framework/techstack có trong dự án -->
- **Spring Boot (Java):** `controller` / `grpc` → `service` → `repository`/`dao` → `entity`/`model` → `dto` → `config`
- **Node.js / Express / NestJS:** `controller` / `resolver` → `service` → `repository` / `entity` → `dto` / `interface` → `config`
- **React (TypeScript/JavaScript):** `router` → `view`/`page` → `component` → `store`/`slice`/`thunk` → `api service`
- **Angular (TypeScript):** `routing-module` → `page`/`component` → `service` → `model`
- **Vue (TypeScript/JavaScript):** `router` → `views`/`pages` → `components` → `stores`/`pinia` → `api`

### 10.2 Service Quick Matrix & Verification Commands (`{{VERIFY_COMMANDS}}`)

| Service | Thứ tự đọc source code (`{{LAYER_READ_ORDER}}`) | Lệnh xác thực (`{{VERIFY_COMMANDS}}`) | Ràng buộc kỹ thuật |
|---|---|---|---|
| `{{service-key-1}}` | `{{controller}}` → `{{service}}` → `{{repository}}` → `{{model}}` → `{{config}}` | `{{mvn clean test / npm test}}` | {{Ràng buộc kiến trúc, security, không code logic ở controller}} |
| `{{service-key-2}}` | `{{router}}` → `{{views}}` → `{{components}}` → `{{store}}` → `{{api}}` | `{{npm run build / npm test}}` | {{Quy chuẩn UI/UX, xử lý state/error bắt buộc}} |
| `{{service-key-3}}` | `{{grpc/service}}` → `{{worker}}` → `{{client}}` → `{{config}}` | `{{mvn clean test / pytest / go test}}` | {{Ràng buộc về hiệu năng, timeout, transaction}} |

### 10.3 Deploy & release commands (`{{DEPLOY_COMMANDS}}`)

| Service | Build artifact / Image | Kịch bản / Lệnh deploy | Rollback | Hiện trạng CI/CD |
|---|---|---|---|---|
| `{{service-key-1}}` | `{{BUILD_PACKAGE_CMD}}` | `{{DEPLOY_SCRIPT_OR_K8S}}` | `{{ROLLBACK_CMD}}` | {{CI/CD status, ví dụ: GitLab CI / Jenkins / K8s}} |
| `{{service-key-2}}` | `{{BUILD_PACKAGE_CMD}}` | `{{DEPLOY_SCRIPT_OR_K8S}}` | `{{ROLLBACK_CMD}}` | {{CI/CD status}} |
| `{{service-key-3}}` | `{{BUILD_PACKAGE_CMD}}` | `{{DEPLOY_SCRIPT_OR_K8S}}` | `{{ROLLBACK_CMD}}` | {{CI/CD status}} |

*Ghi chú:* Xem catalog lệnh chi tiết tại `docs/COMMANDS.md`.
---
## 11. Agent working rules [REQUIRED]

### 11.1 Project Configuration Defaults
- **DB docs path (`{{DB_DOCS_PATH}}`):** `docs/database/` (nếu có, snapshot, migration Liquibase/Flyway/SQL script tại repo tương ứng).
- **Impact tool (`{{IMPACT_TOOL}}`):** `none` (hoặc tên công cụ phân tích impact nếu có; mặc định sử dụng git diff và source tracing theo `{{LAYER_READ_ORDER}}`).
- **I18N requirement (`{{I18N_REQUIRED}}`):** `{{false | true}}` (mặc định ngôn ngữ chính, chỉ bật `true` nếu hệ thống yêu cầu đa ngôn ngữ bắt buộc).
- **Integration surfaces (`{{INTEGRATION_SURFACES}}`):**
  - {{Giao tiếp RPC/Protobuf, ví dụ: gRPC Protobuf contracts tại `*/src/main/resources/proto/*.proto`}}
  - {{REST APIs, ví dụ: REST API endpoints / OpenAPI specs}}
  - {{Message Broker events / topic schema}}
  - {{Giao thức tích hợp bên thứ ba / External integrations}}
- **Status vocabulary (`{{STATUS_VOCABULARY}}`):** `draft` → `plan-review` → `approved` → `in_progress` → `testing` → `done` (`blocked` / `cancelled`)
- **Task format (`{{TASK_FORMAT}}`):** `checklist`

### 11.2 Phạm vi và an toàn
- Không triển khai bất kỳ tính năng nào ngoài phạm vi đã được duyệt trong `expect.md` / `plan.md` / `tasks.md`.
- Cập nhật liên tục trạng thái trong `tasks.md` khi tiến hành công việc.
- `report.md` phải phản ánh file thay đổi thực tế và kết quả test thực tế (`{{REPORT_EVIDENCE}}`).
- Tuyệt đối không commit hoặc ghi secrets, API keys, password, certificate private key vào code hoặc tài liệu.
- Không chỉnh sửa file build artifact (`dist/`, `target/`, `node_modules/`, `build/`).
- **Dependency policy (`{{DEPENDENCY_POLICY}}`):** {{Quy định thêm thư viện mới, ví dụ: Không tự ý thêm dependency mới nếu chưa được phê duyệt tại Gate 1}}.
- **Forbidden changes (`{{FORBIDDEN_CHANGES}}`):** {{Các thay đổi bắt buộc phải dừng lại xin phê duyệt lại, ví dụ: Thay đổi API/Protobuf public contract, DB schema, RBAC/Security}}.
- **Deploy triggers (`{{DEPLOY_TRIGGERS}}`):** {{Các loại thay đổi bắt buộc tạo deploy.md, ví dụ: DB migration, cấu hình/env, dependency mới, scheduled job, contract}}.
- **Mockable integrations (`{{MOCKABLE_INTEGRATIONS}}`):** {{Danh sách dịch vụ được phép mock ở local, ví dụ: Gateway, Payment, Third-party APIs}}.

### 11.3 Quy chuẩn code (`{{CODE_STYLE_RULES}}`)
- Tuân thủ cấu trúc phân tầng: Controller/Handler → Service/Business Engine → Repository/Client Adapter.
- Thứ tự implement files trong task (`{{IMPLEMENT_ORDER}}`):
  - Backend: Entity/Migration/DTO → Repository → Service → Controller/gRPC Handler → Config/Test
  - Frontend: Types/Models → API Service → Store/State → Components → Pages/Routes
- Không đặt logic xử lý nghiệp vụ tại tầng Controller/View.
- Mọi file tạo mới phải ở định dạng **UTF-8 without BOM**.
- Phản hồi và comment code bằng **{{Vietnamese | English}}**.

### 11.4 Common impact zones (`{{COMMON_IMPACT_ZONES}}`)

| Thay đổi (Change X) | Ảnh hưởng tới (Affects Y) | Mức độ rủi ro | Hành động bắt buộc |
|---|---|---|---|
| {{Thay đổi giao tiếp API/Protobuf/RPC}} | {{Tất cả client và service phụ thuộc}} | **CAO (HIGH)** | {{Cập nhật đồng bộ client SDK/contract, kiểm tra tương thích ngược}} |
| {{Thay đổi schema/cấu trúc dữ liệu core}} | {{Báo cáo, luồng xử lý giao dịch chính}} | **CAO (HIGH)** | {{Tạo migration script, đánh giá dữ liệu cũ}} |
| {{Thay đổi cấu hình auth/security}} | {{Luồng đăng nhập và xác thực người dùng}} | **CAO (HIGH)** | {{Test kỹ lưỡng các scenario phân quyền và token}} |
---

## 12. Project skills [OPTIONAL]

| Tình huống | Kỹ năng (`docs/skills/`) |
|---|---|
| Khởi tạo hoặc cập nhật tài liệu toàn hệ thống | `docs/skills/init-docs/SKILL.md` |
| Tạo kế hoạch kỹ thuật cho ticket mới | `docs/skills/create-plan/SKILL.md` |
| Thực thi task và viết mã nguồn | `docs/skills/implement-task/SKILL.md` |
| Tạo kịch bản kiểm thử từ yêu cầu | `docs/skills/create-testcase/SKILL.md` |

---

## 13. Git rules [REQUIRED] (`{{BRANCH_RULE}}`, `{{COMMIT_RULE}}`)

### 13.1 Branch convention (`{{BRANCH_RULE}}`)
- Tên branch: `feature/{{TICKET_PREFIX}}-<TICKET-NUMBER>-<slug>` hoặc `feature/{{TICKET_PREFIX}}-<TICKET-NUMBER>` (ví dụ: `feature/{{TICKET_PREFIX}}-1024-user-auth` hoặc `feature/{{TICKET_PREFIX}}-1024`) — **đồng nhất trên tất cả các repo tham gia**.
- Kiểm tra branch trước khi làm việc: `git status`.
- Tuyệt đối không chuyển branch khi working tree chưa sạch (chưa commit/stash).

### 13.2 Commit & Push (`{{COMMIT_RULE}}`)
1. `git status` để kiểm tra thay đổi.
2. Kiểm tra `git diff` và `git diff --staged`.
3. Format commit message: `<TICKET-ID>: <mô tả ngắn gọn>` (ví dụ `{{TICKET_PREFIX}}-1024: add redis caching layer`).
4. `git push origin <current-branch>`.
5. **Agent không tự ý commit/push/merge trừ khi được yêu cầu rõ ràng.**

---

## 14. Do not modify unless explicitly requested [REQUIRED]

- `node_modules/`, `target/`, `build/`, `dist/`, `.idea/`, `.vscode/`
- `.env*`, keystores (`.jks`, `.p12`), certificates, private keys, secrets, credentials
- Log files, caches, database dump files ngoài `docs/database/`

---

## 15. Quick links [REQUIRED]

> **Lưu ý:** Các link dưới đây là đường dẫn tương đối tính từ thư mục gốc của dự án sau khi đã copy file này ra root (`AGENTS.md`).

- [docs/README.md](docs/README.md) — Tổng quan tài liệu
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — Kiến trúc hệ thống
- [docs/DESIGN.md](docs/DESIGN.md) — Thiết kế giao diện UI/UX
- [docs/COMMANDS.md](docs/COMMANDS.md) — Catalog lệnh tắt
- [docs/specs/](docs/specs/) — Đặc tả nghiệp vụ
- [docs/rules/](docs/rules/) — Quy tắc vận hành
- [docs/features/](docs/features/) — Quản lý tickets/features
- [docs/skills/](docs/skills/) — Danh mục kỹ năng
