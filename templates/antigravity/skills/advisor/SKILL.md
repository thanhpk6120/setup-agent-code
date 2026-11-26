---
name: advisor
description: Configure or inspect the Independent Reviewer (review-gate) model and enabled state. Use when the user runs /advisor [inherit|flash_lite|flash|pro|<model-id>|on|off|status] to switch reviewer speed/model or toggle review-gate.
---

# /advisor — Configure Independent Reviewer (`review-gate`)

Manage the Stop-hook Independent Reviewer configuration stored at `~/.gemini/antigravity-cli/review-gate.json` (on Windows: `%USERPROFILE%\.gemini\antigravity-cli\review-gate.json`).

## Valid Settings

- `model`:
  - Subagent tiers (runs via `invoke_subagent`): `"inherit"` | `"flash_lite"` | `"flash"` | `"pro"` (default: `"inherit"`)
  - Exact model ID (runs via `review-gate.mjs --run` using `agy` `stdin` `stream-json`, passing full `git diff` or non-git file contents up to ~120 KB in 1 turn, auto-filtering lockfiles, with temporary patch file fallback cleaned to Trash after review, 180s timeout): any model ID from `agy models` matching `^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$` (e.g., `"gemini-4-neon-high"`, `"gemini-4-neon-medium"`, `"claude-sonnet-5-5-high"`, `"claude-opus-5-5-medium"`)
- `enabled`: `true` | `false` (default: `true`)

## Behavior by Argument

Read the existing JSON file first (if missing or invalid, treat as `{"enabled": true, "model": "inherit"}`):

1. **No argument or `status`** (case-insensitive):
   - Do not modify the file.
   - Report the current `enabled` and `model` values, plus valid options (`inherit`, `flash_lite`, `flash`, `pro`, `<model-id>` from `agy models`, `on`, `off`).
2. **`on` or `enable`** (case-insensitive):
   - Set `enabled: true` (keep existing `model`, or `"inherit"` if unset).
   - Write the updated JSON back and confirm.
3. **`off` or `disable`** (case-insensitive):
   - Set `enabled: false` (keep existing `model`, or `"inherit"` if unset).
   - Write the updated JSON back and confirm.
4. **Tier (`inherit`, `flash_lite`, `flash`, `pro`, case-insensitive, normalizing `flash-lite` -> `flash_lite`) OR an exact model ID**:
   - First check fixed keywords (`status`, `on`, `enable`, `off`, `disable`, `flash-lite`, and the 4 tiers `inherit`, `flash_lite`, `flash`, `pro`) case-insensitively.
   - If the argument is not one of those keywords, validate it matches `^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$` AND appears as an exact first-column model ID on a model row in `agy models` output (ignore header/status lines). If `agy models` fails (non-zero exit, not logged in, or `agy` unavailable) or does not list the ID, fail closed: do NOT modify `review-gate.json` and report the error or usage.
   - Once validated, set `model` to the normalized lowercase tier (`"inherit"`, `"flash_lite"`, `"flash"`, or `"pro"`) for tiers, or the exact matched model ID from `agy models` for exact model IDs (keep existing `enabled`, or `true` if unset).
   - Write the updated JSON back to `review-gate.json`.
   - Confirm the new active configuration in 1-2 lines.
5. **Any other argument (whitespace-only, contains spaces, invalid characters, or unknown model ID)**:
   - Do not modify `review-gate.json`.
   - Show usage: `/advisor [inherit|flash_lite|flash|pro|<model-id>|on|off|status]`.
