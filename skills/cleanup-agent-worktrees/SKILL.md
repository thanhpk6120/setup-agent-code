---
name: cleanup-agent-worktrees
description: "Use when you need to quickly preview or remove Codex agent git worktrees under .Codex/worktrees/agent-* for the current repo or another repo path."
---

# Cleanup Codex Agent Worktrees

## When to Use

- "Xóa hết worktree agent"
- "Dọn Codex agent worktree"
- "Preview các agent worktree sẽ bị xóa"
- "Cleanup worktree agent cho repo khác"
- "Xóa tất cả worktree agent trên mọi repo"

## What This Uses

Script:
- `bin/cleanup-agent-worktrees.ps1`

The script:
- previews by default
- targets only `.Codex/worktrees/agent-*`
- skips the current worktree automatically
- unlocks locked worktrees before removal
- uses `git worktree remove --force` (double force for stubborn ones)
- prunes git worktree metadata after apply (SmartGit and other tools see clean state)
- removes orphan directories only when `-IncludeOrphans` is passed
- supports `-ScanRoot` to scan all repos under a directory recursively

## Safety Notes

- `-Apply` is destructive for the selected worktrees.
- Review `WOULD-REMOVE` in preview mode before using `-Apply`.
- `git worktree prune` ensures SmartGit, GitKraken, and other git GUIs reflect the cleanup.

## Commands

### Preview current repo

```powershell
powershell -File "$env:USERPROFILE\.Codex\skills\cleanup-agent-worktrees\bin\cleanup-agent-worktrees.ps1"
```

### Apply cleanup for current repo

```powershell
powershell -File "$env:USERPROFILE\.Codex\skills\cleanup-agent-worktrees\bin\cleanup-agent-worktrees.ps1" -Apply
```

### Preview a specific repo

```powershell
powershell -File "$env:USERPROFILE\.Codex\skills\cleanup-agent-worktrees\bin\cleanup-agent-worktrees.ps1" -RepoRoot "D:\path\to\repo"
```

### Apply cleanup for another repo

```powershell
powershell -File "$env:USERPROFILE\.Codex\skills\cleanup-agent-worktrees\bin\cleanup-agent-worktrees.ps1" -RepoRoot "D:\path\to\repo" -Apply
```

### Scan ALL repos under a directory (global cleanup)

```powershell
powershell -File "$env:USERPROFILE\.Codex\skills\cleanup-agent-worktrees\bin\cleanup-agent-worktrees.ps1" -ScanRoot "D:\Project" -Apply
```

### Include orphan directories too

```powershell
powershell -File "$env:USERPROFILE\.Codex\skills\cleanup-agent-worktrees\bin\cleanup-agent-worktrees.ps1" -Apply -IncludeOrphans
```

## Verification

- Check `SKIP-CURRENT` to confirm the active worktree was not removed.
- Check `WOULD-REMOVE` in preview mode before using `-Apply`.
- After apply, run `git worktree list` to confirm remaining worktrees.
- SmartGit/GitKraken: refresh the repo view — pruned metadata means stale entries disappear.
