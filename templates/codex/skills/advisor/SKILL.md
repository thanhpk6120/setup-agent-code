---
name: advisor
description: Configure or inspect the Independent Reviewer (review-gate) model and enabled state. Use when the user runs /advisor [inherit|<model>|on|off|status] to switch reviewer model or toggle review-gate.
---

# /advisor — Configure Independent Reviewer (`review-gate`)

Manage the Stop-hook Independent Reviewer configuration stored at `~/.codex/review-gate.json` (on Windows: `%USERPROFILE%\.codex\review-gate.json`).

## Valid Settings

- `model`: `"inherit"` or a valid Codex model name with no spaces (default: `"inherit"`)
- `enabled`: `true` | `false` (default: `true`)

## Behavior by Argument

Read the existing JSON file first (if missing or invalid, treat as `{"enabled": true, "model": "inherit"}`):

1. **No argument or `status`**:
   - Do not modify the file.
   - Report the current `enabled` and `model` values, plus valid commands (`inherit`, `<model>`, `on`, `off`).
2. **`on` or `enable`**:
   - Set `enabled: true` (keep existing `model`, or `"inherit"` if unset).
   - Write the updated JSON back and confirm.
3. **`off` or `disable`**:
   - Set `enabled: false` (keep existing `model`, or `"inherit"` if unset).
   - Write the updated JSON back and confirm.
4. **Any valid model name (`inherit` or a non-empty model string without spaces)**:
   - Set `model` to the requested value (keep existing `enabled`, or `true` if unset).
   - Write the updated JSON back and confirm.
5. **Invalid argument (contains spaces or empty)**:
   - Do not modify `review-gate.json`.
   - Show usage: `/advisor [inherit|<model>|on|off|status]`.
