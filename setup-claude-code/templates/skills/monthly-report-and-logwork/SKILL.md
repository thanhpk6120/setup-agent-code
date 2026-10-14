---
name: monthly-report-and-logwork
description: Audit Confluence meeting notes and Jira tasks for the month to build a complete monthly report, fill missing days, and automatically log 8 hours/day to Jira.
---

# Skill: Monthly Report & Worklog Automation

> **Goal:** Automate monthly work reconciliation: Read Confluence Meeting Notes + Jira Issues/Changelogs -> Build complete `monthly-report-YYYY-MM.md` table (including days without notes) -> Automatically log exactly 8 hours/day (positive integers) to Jira.

---

## Workflow (4 Steps)

### Step 1: Identify Personal Info & Date Range
1. Read personal details from `personal.md` (Full name, Username / Jira Key, Email).
2. Determine report month and year (e.g. `YYYY-MM`).
3. Compile a list of **all working days** in the month (Monday through Friday, excluding Saturday, Sunday, and official statutory holidays).

---

### Step 2: Collect Data from Confluence & Jira

#### 2.1. Read Confluence Meeting Notes
1. Use `confluence_get_page_children` or `confluence_search` tool in space `CT` and parent page for the corresponding month (Structure: `Meeting Notes` -> `Year YYYY` -> `Month MM`).
2. For each day with a note:
   - Read work assignment table content.
   - Locate row corresponding to the member (by name or `@mention`).
   - Extract Jira ticket keys (`issue_key`), task descriptions, blockers, suggestions.

#### 2.2. Cross-check Jira Audit & Find Tasks for Days Lacking Notes
1. Use `jira_search` with JQL:
   ```jql
   assignee = '<username>' AND ((created >= 'YYYY-MM-01' AND created <= 'YYYY-MM-31 23:59') OR (updated >= 'YYYY-MM-01' AND updated <= 'YYYY-MM-31 23:59'))
   ```
2. For days **lacking a Meeting Note page** on Confluence:
   - Check `changelog` and `updated`/`created` timestamps of each Jira issue to identify exactly which tasks were worked on that day.
   - Verify `project` and `assignee` to ensure 100% correct project and assignee matching.

---

### Step 3: Generate Monthly Report File (`monthly-report-YYYY-MM.md`)
Create or update `monthly-report-YYYY-MM.md` with standard structure:

1. **4 Focus Work Areas (High-Level Summary):**
   - Format: `[Project Name] Summary of primary work focus`
2. **Daily Breakdown Table:**
   - Columns: `Date` | `Day of Week` | `Meeting Note` (✅ Yes / ❌ No) | `Task Key` | `Project` | `Work Content / Summary` | `Status`
3. **Monthly Tasks Master Table:**
   - Columns: `No.` | `Task Key` | `Project` | `Task Summary` | `Current Status`

---

### Step 4: Automatically Log Work to Jira (`jira_add_worklog`)

#### Worklog Rules:
1. **Full duration:** Each working day must be logged for **exactly 8 hours** (monthly total = working days * 8h).
2. **Time allocation:** Use only **positive integers** (e.g.: `2h`, `4h`, `8h`), no fractional hours or minutes (`1h30m`, `3.5h` are invalid).
   - If a day has 1 task: Log `8h` to that task.
   - If a day has 2 tasks: Log `4h` + `4h`.
   - If a day has 4 tasks: Log `2h` + `2h` + `2h` + `2h`.
3. **Comment:** Extract **verbatim / faithful summary** from task `summary`, `description`, or `changelog`. **Never fabricate descriptions.**
4. **Start time (`started`):** Set to early morning of that working day (ISO format: `YYYY-MM-DDTHH:mm:ss.000+0700` or equivalent).
