---
name: monthly-report-and-logwork
description: Review Confluence meeting notes and Jira tasks for the month to build a complete monthly report, fill missing days, and auto-log 8 hours/day of worklogs to Jira.
---

# Skill: Monthly Report & Worklog Automation

> **Goal:** Automate the monthly work reconciliation: Read Confluence Meeting Notes + Jira Issues/Changelogs -> Build a complete `monthly-report-YYYY-MM.md` table (including days without notes) -> Auto-log 8 hours/day (positive integers) to Jira.

---

## Execution workflow (4 steps)

### Step 1: Identify personal info and time range
1. Read personal info from `personal.md` (full name, Jira username / key, email).
2. Determine the report month and year (e.g. `YYYY-MM`).
3. List **all working days** in the month (Monday to Friday, excluding Saturday, Sunday, and official public holidays).

---

### Step 2: Collect data from Confluence and Jira

#### 2.1. Read Confluence meeting notes
1. Use `confluence_get_page_children` or `confluence_search` with the `CT` space and the matching month parent page (Structure: `Meeting Notes` -> `Year YYYY` -> `Month MM`).
2. For each day with notes:
   - Read the task assignment table.
   - Find the row for the member (by full name or `@mention`).
   - Extract the Jira ticket list (`issue_key`), work description, blockers, and suggestions.

#### 2.2. Reconcile Jira audit and find tasks for days without notes
1. Use `jira_search` with JQL:
   ```jql
   assignee = '<username>' AND ((created >= 'YYYY-MM-01' AND created <= 'YYYY-MM-31 23:59') OR (updated >= 'YYYY-MM-01' AND updated <= 'YYYY-MM-31 23:59'))
   ```
2. For days **without a Meeting Note page** on Confluence:
   - Check each Jira issue `changelog` and `updated`/`created` timestamps to pin down exactly which task you worked on that day.
   - Verify `project` and `assignee` to ensure 100% the right project and the right assignee.

---

### Step 3: Create the monthly report file (`monthly-report-YYYY-MM.md`)
Create or update `monthly-report-YYYY-MM.md` with the standard structure:

1. **4 focus work groups (High-Level Summary):**
   - Format: `[Project Name] Summary of the main work group`
2. **Per-working-day summary table:**
   - Columns: `Date` | `Weekday` | `Meeting Note` (has / missing) | `Task Key` | `Project` | `Work Content / Summary` | `Status`
3. **Full-month task list table:**
   - Columns: `No.` | `Task Key` | `Project` | `Task Summary` | `Current Status`

---

### Step 4: Auto-log work to Jira (`jira_add_worklog`)

#### Worklog rules:
1. **Full duration:** Each working day must log **exactly 8 hours** (month total = working days * 8h).
2. **Split time:** Use **positive integers only** (e.g. `2h`, `4h`, `8h`); no fractions or minutes (`1h30m`, `3.5h` are invalid).
   - 1 task in a day: log `8h` on it.
   - 2 tasks in a day: log `4h` + `4h`.
   - 4 tasks in a day: log `2h` + `2h` + `2h` + `2h`.
3. **Content (comment):** Quote or faithfully summarize from the task `summary`, `description`, or `changelog`. **Never invent content.**
4. **Start time (`started`):** Set to early morning of that working day (ISO format: `YYYY-MM-DDTHH:mm:ss.000+0700` or equivalent).
