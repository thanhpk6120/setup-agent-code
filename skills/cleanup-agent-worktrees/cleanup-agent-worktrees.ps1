param(
    [string]$RepoRoot,
    [string]$Pattern = 'agent-*',
    [switch]$Apply,
    [switch]$IncludeOrphans
)

$ErrorActionPreference = 'Stop'

if ($Pattern -notlike 'agent-*' -or $Pattern.Contains('\') -or $Pattern.Contains('/')) {
    throw 'Pattern must stay within the agent-* namespace, for example: agent-* or agent-a*.'
}

function Get-NormalizedPath {
    param([string]$Path)

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    return $item.FullName.TrimEnd([char[]]@('\', '/')).ToLowerInvariant()
}

function Test-PathPrefix {
    param(
        [string]$Path,
        [string]$Prefix
    )

    $normalizedPath = $Path.TrimEnd([char[]]@('\', '/'))
    $normalizedPrefix = $Prefix.TrimEnd([char[]]@('\', '/'))

    return $normalizedPath.Equals($normalizedPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith($normalizedPrefix + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
        $normalizedPath.StartsWith($normalizedPrefix + '/', [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-ResolvedRepoRoot {
    param([string]$InputRepoRoot)

    if ($InputRepoRoot) {
        $probePath = (Get-Item -LiteralPath $InputRepoRoot -ErrorAction Stop).FullName
        $topLevel = git -C $probePath rev-parse --show-toplevel 2>$null
        if (-not $?) {
            throw 'Cannot determine git top-level from -RepoRoot.'
        }

        $topLevel = $topLevel.Trim()
        if (-not $topLevel) {
            throw 'git top-level is empty.'
        }

        return $topLevel
    }

    $commonDir = git rev-parse --path-format=absolute --git-common-dir 2>$null
    if (-not $?) {
        throw 'Cannot determine git common dir. Run this script inside a git repository or pass -RepoRoot.'
    }

    $commonDir = $commonDir.Trim()
    if (-not $commonDir) {
        throw 'git common dir is empty.'
    }

    return (Split-Path -Path $commonDir -Parent)
}

function Test-WorktreeDirty {
    param([string]$WorktreePath)

    $statusLines = git -C $WorktreePath status --porcelain 2>$null
    if (-not $?) {
        throw "Cannot inspect worktree status: $WorktreePath"
    }

    return ($statusLines | Measure-Object).Count -gt 0
}

function Assert-SafeToRemove {
    param([string]$WorktreePath)

    if (Test-WorktreeDirty -WorktreePath $WorktreePath) {
        throw 'worktree has uncommitted changes; review it manually before using -Apply.'
    }
}

function Get-RegisteredWorktrees {
    param([string]$Root)

    $lines = git -C $Root worktree list --porcelain
    if (-not $?) {
        throw 'Cannot list git worktrees.'
    }

    $paths = @()
    foreach ($line in $lines) {
        if ($line -like 'worktree *') {
            $paths += $line.Substring(9).Trim()
        }
    }

    return $paths
}

$resolvedRepoRoot = Get-ResolvedRepoRoot -InputRepoRoot $RepoRoot
$worktreeRoot = Join-Path $resolvedRepoRoot '.claude\worktrees'
$currentPath = (Get-Location).Path
$currentNormalized = $null
try {
    $currentNormalized = Get-NormalizedPath -Path $currentPath
} catch {
    $currentNormalized = $currentPath.TrimEnd([char[]]@('\', '/')).ToLowerInvariant()
}

$registeredPaths = Get-RegisteredWorktrees -Root $resolvedRepoRoot
$registeredCandidates = @()
$normalizedWorktreeRoot = $worktreeRoot.TrimEnd([char[]]@('\', '/')).ToLowerInvariant()

foreach ($registeredPath in $registeredPaths) {
    $parentPath = Split-Path -Path $registeredPath -Parent
    $leafName = Split-Path -Path $registeredPath -Leaf
    $normalizedParent = $parentPath.TrimEnd([char[]]@('\', '/')).ToLowerInvariant()

    if (-not $normalizedParent.Equals($normalizedWorktreeRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
    }

    if ($leafName -notlike $Pattern) {
        continue
    }

    $normalizedRegistered = $registeredPath.TrimEnd([char[]]@('\', '/')).ToLowerInvariant()
    $registeredCandidates += [pscustomobject]@{
        Path = $registeredPath
        Leaf = $leafName
        IsCurrent = Test-PathPrefix -Path $currentNormalized -Prefix $normalizedRegistered
    }
}

$wouldRemove = @()
$skippedCurrent = @()
$removed = @()
$failed = @()
$orphanRemoved = @()
$orphanSkipped = @()

foreach ($candidate in $registeredCandidates) {
    if ($candidate.IsCurrent) {
        $skippedCurrent += $candidate.Path
        continue
    }

    $wouldRemove += $candidate.Path

    if (-not $Apply) {
        continue
    }

    try {
        Assert-SafeToRemove -WorktreePath $candidate.Path
        git -C $resolvedRepoRoot worktree remove --force "$($candidate.Path)"
        if (-not $?) {
            throw 'git worktree remove returned non-zero exit code.'
        }
        $removed += $candidate.Path
    } catch {
        $failed += "$($candidate.Path) :: $($_.Exception.Message)"
    }
}

if ($Apply) {
    git -C $resolvedRepoRoot worktree prune | Out-Null
    if (-not $?) {
        throw 'git worktree prune returned non-zero exit code.'
    }
}

if ($IncludeOrphans -and (Test-Path -LiteralPath $worktreeRoot)) {
    $registeredSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($candidate in $registeredCandidates) {
        [void]$registeredSet.Add($candidate.Path)
    }

    Get-ChildItem -LiteralPath $worktreeRoot -Directory -Filter $Pattern | ForEach-Object {
        $orphanPath = $_.FullName
        if ($registeredSet.Contains($orphanPath)) {
            return
        }

        $normalizedOrphan = $orphanPath.TrimEnd([char[]]@('\', '/')).ToLowerInvariant()
        if (Test-PathPrefix -Path $currentNormalized -Prefix $normalizedOrphan) {
            $orphanSkipped += $orphanPath
            return
        }

        if (-not $Apply) {
            $orphanSkipped += "$orphanPath :: preview-only"
            return
        }

        try {
            Remove-Item -LiteralPath $orphanPath -Recurse -Force -Confirm:$false
            $orphanRemoved += $orphanPath
        } catch {
            $failed += "$orphanPath :: $($_.Exception.Message)"
        }
    }
}

Write-Host "RepoRoot: $resolvedRepoRoot"
Write-Host "WorktreeRoot: $worktreeRoot"
Write-Host "Mode: $(if ($Apply) { 'apply' } else { 'preview' })"
Write-Host ''

Write-Host 'WouldRemove:'
if ($wouldRemove.Count -eq 0) {
    Write-Host '  - none'
} else {
    $wouldRemove | ForEach-Object { Write-Host "  - $_" }
}

Write-Host 'SkippedCurrent:'
if ($skippedCurrent.Count -eq 0) {
    Write-Host '  - none'
} else {
    $skippedCurrent | ForEach-Object { Write-Host "  - $_" }
}

Write-Host 'Removed:'
if ($removed.Count -eq 0) {
    Write-Host '  - none'
} else {
    $removed | ForEach-Object { Write-Host "  - $_" }
}

Write-Host 'OrphanRemoved:'
if ($orphanRemoved.Count -eq 0) {
    Write-Host '  - none'
} else {
    $orphanRemoved | ForEach-Object { Write-Host "  - $_" }
}

Write-Host 'OrphanSkipped:'
if ($orphanSkipped.Count -eq 0) {
    Write-Host '  - none'
} else {
    $orphanSkipped | ForEach-Object { Write-Host "  - $_" }
}

Write-Host 'Failed:'
if ($failed.Count -eq 0) {
    Write-Host '  - none'
} else {
    $failed | ForEach-Object { Write-Host "  - $_" }
}
