#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
    Verify that a patch set applies to a GNU nano release and builds.
.DESCRIPTION
    Creates a throwaway jj workspace, extracts the given nano release into it,
    applies the patch set in filename order with git am --reject, and runs the
    build. The current workspace is never modified.

    This is the pass bar for a patch renew: git am must succeed for every patch
    and the build must be green. It is also the manual way to check a frozen
    snapshot still applies to its own tarball:

      pwsh -nop .../verify-patches.ps1 -Version 9.2

    -Version always names a real upstream release and the patch set is
    patches/<Version>. To test the working set instead, pass -WorkingSet, which
    applies patches/latest but still builds against -Version. A renewal in
    progress uses that pairing, because patches/latest is not yet a versioned
    directory.

    The workspace is removed on success and kept on failure, so rejected hunks
    can be inspected.
.PARAMETER Version
    The upstream release to build against, e.g. 9.3.
.PARAMETER WorkingSet
    Apply patches/latest instead of patches/<Version>.
.PARAMETER KeepWorkspace
    Keep the throwaway workspace even on success.
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Version,

    [Parameter(Mandatory = $false)]
    [switch]$WorkingSet,

    [Parameter(Mandatory = $false)]
    [switch]$KeepWorkspace
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/common.ps1"

foreach ($tool in @('jj', 'git', 'pixi', 'tar')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "Required '$tool' command not found." -ForegroundColor Red
        exit 1
    }
}

if ($Version -eq 'latest') {
    Write-Host "-Version must be a release such as 9.3, not 'latest'." -ForegroundColor Red
    Write-Host "To verify the working set against a release, use: -Version 9.3 -WorkingSet" -ForegroundColor Yellow
    exit 1
}

if ($Version -notmatch '^\d+(\.\d+)+$') {
    Write-Host "-Version must be an upstream release such as 9.3, got '$Version'." -ForegroundColor Red
    exit 1
}

$setName = if ($WorkingSet) { 'latest' } else { $Version }
$resolvedPatchesDir = Join-Path $script:PatchesRoot $setName

if (-not (Test-Path -LiteralPath $resolvedPatchesDir)) {
    $available = @(Get-ChildItem -LiteralPath $script:PatchesRoot -Directory -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Name | Sort-Object)
    Write-Host "No patch set at patches/$setName." -ForegroundColor Red
    if ($available.Count -gt 0) {
        Write-Host "Available patch sets: $($available -join ', ')" -ForegroundColor Yellow
    }
    exit 1
}

$targetVersion = $Version


$workspaceName = "verify-nano-$targetVersion"
$workspacePath = Join-Path $script:CacheDir "verify/$targetVersion"

if (Test-Path -LiteralPath $workspacePath) {
    Write-Host "Removing leftover workspace at $workspacePath" -ForegroundColor Yellow
    & jj workspace forget $workspaceName 2>$null
    Remove-Item -LiteralPath $workspacePath -Recurse -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Path $workspacePath -Force | Out-Null

function Remove-VerifyWorkspace {
    if ($KeepWorkspace) {
        Write-Host "Kept workspace at $workspacePath" -ForegroundColor Yellow
        return
    }
    & jj workspace forget $workspaceName 2>$null
    Remove-Item -LiteralPath $workspacePath -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Creating workspace $workspaceName at $workspacePath..." -ForegroundColor Cyan
& jj workspace add --name $workspaceName --revision 'root()' $workspacePath
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to create jj workspace." -ForegroundColor Red
    Remove-Item -LiteralPath $workspacePath -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}

try {
    Push-Location $workspacePath

    $tarball = Get-NanoReleaseTarball -Version $targetVersion
    Expand-NanoTarball -TarballPath $tarball -Destination $workspacePath

    # pixi runs tasks from the manifest's directory and configure.sh resolves the
    # project root from its own path, so the workspace needs its own copies of
    # both. Without this the build would silently target the real repo.
    Copy-Item -LiteralPath (Join-Path $script:PatchToolsRoot "pixi.toml") -Destination $workspacePath
    Copy-Item -LiteralPath (Join-Path $script:PatchToolsRoot "scripts") -Destination $workspacePath -Recurse
    $lockFile = Join-Path $script:PatchToolsRoot "pixi.lock"
    if (Test-Path -LiteralPath $lockFile) {
        Copy-Item -LiteralPath $lockFile -Destination $workspacePath
    }

    & git init --quiet
    & git config user.name 'nano-for-windows'
    & git config user.email 'noreply@chawyehsu.com'
    & git add -A
    & git commit --quiet -m "nano: v$targetVersion"

    $result = Invoke-GitAmPatches -PatchesDir $resolvedPatchesDir
    if ($result.Failed.Count -gt 0) {
        Write-Host "Patch application failed: $($result.Failed -join ', ')" -ForegroundColor Red
        Write-Host "Workspace kept for inspection at $workspacePath" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "All $($result.Applied) patches applied. Building..." -ForegroundColor Cyan
    & pixi run build
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Build failed." -ForegroundColor Red
        Write-Host "Workspace kept for inspection at $workspacePath" -ForegroundColor Yellow
        exit 1
    }

    Write-Host "Verified: nano $targetVersion applies and builds with $resolvedPatchesDir." -ForegroundColor Green
} finally {
    Pop-Location
    Remove-VerifyWorkspace
}
