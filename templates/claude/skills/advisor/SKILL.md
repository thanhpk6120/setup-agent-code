---
name: advisor
description: Configure or inspect the Independent Reviewer (review-gate) model and enabled state. Use when the user runs /advisor [inherit|haiku|sonnet|opus|on|off|status] to switch reviewer speed/model or toggle review-gate.
---

# /advisor — Configure Independent Reviewer (`review-gate`)

Manage the Stop-hook Independent Reviewer configuration stored at `~/.claude/review-gate.json` (on Windows: `%USERPROFILE%\.claude\review-gate.json`).

## Valid Settings

- `model`: `"inherit"` | `"haiku"` | `"sonnet"` | `"opus"` (default: `"inherit"`)
- `enabled`: `true` | `false` (default: `true`)

## Behavior by Argument

Read the existing JSON file first (if missing or invalid, treat as `{"enabled": true, "model": "inherit"}`):

1. **No argument or `status`**:
   - Do not modify the file.
   - Report the current `enabled` and `model` values, plus the valid options (`inherit`, `haiku`, `sonnet`, `opus`, `on`, `off`).
2. **`inherit`, `haiku`, `sonnet`, or `opus`**:
   - Set `model` to the requested value (keep existing `enabled`, or `true` if unset).
   - Write the updated JSON back to `review-gate.json`.
   - Confirm the new active configuration in 1-2 lines.
3. **`on` or `enable`**:
   - Set `enabled: true` (keep existing `model`, or `"inherit"` if unset).
   - Write the updated JSON back and confirm.
4. **`off` or `disable`**:
   - Set `enabled: false` (keep existing `model`, or `"inherit"` if unset).
   - Write the updated JSON back and confirm.
5. **Any other argument**:
   - Do not modify `review-gate.json`.
   - Show usage: `/advisor [inherit|haiku|sonnet|opus|on|off|status]`.
