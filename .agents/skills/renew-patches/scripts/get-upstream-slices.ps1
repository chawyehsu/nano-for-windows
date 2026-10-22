#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
    Slice an upstream nano diff down to the parts each patch cares about.
.DESCRIPTION
    The release diff between two upstream versions spans the whole tree. A patch
    renew only needs the hunks that touch the files a given patch touches, so
    this script splits the diff per patch and writes one slice per file into
    <OutDir>, named <patch-stem>.diff.

    A slice is empty when upstream did not touch any of that patch's files; such
    patches are reported, since a conflict there cannot be explained by the diff.
.PARAMETER Diff
    Path to the upstream diff, e.g. from
    https://github.com/ahjragaas/nano/compare/v9.2...v9.3.diff
.PARAMETER PatchesDir
    Directory holding the patch set to slice for, e.g. patches/latest.
.PARAMETER OutDir
    Directory to write slices into. Created if missing.
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Diff,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PatchesDir,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutDir
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Diff)) {
    Write-Host "Diff not found: $Diff" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path -LiteralPath $PatchesDir)) {
    Write-Host "Patches directory not found: $PatchesDir" -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

function Get-DiffFileSections {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Lines
    )

    $sections = [ordered]@{}
    $currentPath = $null
    $buffer = New-Object System.Collections.Generic.List[string]

    foreach ($line in $Lines) {
        if ($line -match '^diff --git a/(.+?) b/(.+)$') {
            if ($currentPath) {
                $sections[$currentPath] = $buffer.ToArray() -join "`n"
            }
            $currentPath = $Matches[2]
            $buffer = New-Object System.Collections.Generic.List[string]
            $buffer.Add($line)
            continue
        }

        if ($null -ne $currentPath) {
            $buffer.Add($line)
        }
    }

    if ($currentPath) {
        $sections[$currentPath] = $buffer.ToArray() -join "`n"
    }

    return $sections
}

function Get-PatchTouchedFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PatchPath
    )

    $files = @()
    foreach ($line in Get-Content -LiteralPath $PatchPath) {
        if ($line -match '^diff --git a/(.+?) b/(.+)$') {
            $files += $Matches[2]
        }
    }
    return $files
}

$diffLines = Get-Content -LiteralPath $Diff
$sections = Get-DiffFileSections -Lines $diffLines

$patches = @(Get-ChildItem -LiteralPath $PatchesDir -Filter '*.patch' -File | Sort-Object Name)
if ($patches.Count -eq 0) {
    Write-Host "No patches found in $PatchesDir." -ForegroundColor Red
    exit 1
}

$untouched = @()

foreach ($patch in $patches) {
    $files = Get-PatchTouchedFiles -PatchPath $patch.FullName
    $matched = @()
    foreach ($file in $files) {
        if ($sections.Contains($file)) {
            $matched += $sections[$file]
        }
    }

    $outPath = Join-Path $OutDir ($patch.BaseName + ".diff")
    if ($matched.Count -eq 0) {
        $untouched += $patch.Name
        Set-Content -LiteralPath $outPath -Value "" -NoNewline
        continue
    }

    Set-Content -LiteralPath $outPath -Value ($matched -join "`n") -NoNewline
}

Write-Host "Wrote $($patches.Count) slices to $OutDir." -ForegroundColor Green
if ($untouched.Count -gt 0) {
    Write-Host "Upstream touched none of these patches' files:" -ForegroundColor Yellow
    $untouched | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
}
