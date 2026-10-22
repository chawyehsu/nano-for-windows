#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
    Snapshot the working patch set before renewing it for a new upstream release.
.DESCRIPTION
    Copies patches/latest/*.patch verbatim into patches/<OldVersion>/.

    A snapshot contains .patch files only, and anything else already present in
    the target directory is an error. A target directory that already holds an
    identical copy is a no-op, which makes the step safe to re-run; a target
    directory that differs is refused, because a frozen patch set is a
    historical record and must never be overwritten.

    Run this before touching patches/latest/, so the previous release can still
    be rebuilt from its own patch set.
.PARAMETER OldVersion
    The upstream version the current working set targets, e.g. 9.2. It names the
    directory to create.
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OldVersion
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/common.ps1"

$LatestDir = Join-Path $script:PatchesRoot "latest"

if (-not (Test-Path -LiteralPath $LatestDir)) {
    Write-Host "patches/latest does not exist. Nothing to snapshot." -ForegroundColor Red
    exit 1
}

$targetDir = Join-Path $script:PatchesRoot $OldVersion

if (Test-Path -LiteralPath $targetDir) {
    $foreign = @(Get-ChildItem -LiteralPath $targetDir -File | Where-Object { $_.Extension -ne '.patch' })
    if ($foreign.Count -gt 0) {
        Write-Host "patches/$OldVersion contains non-patch files:" -ForegroundColor Red
        $foreign | ForEach-Object { Write-Host "  $($_.Name)" -ForegroundColor Red }
        exit 1
    }

    $source = @(Get-ChildItem -LiteralPath $LatestDir -Filter '*.patch' -File | Sort-Object Name)
    $existing = @(Get-ChildItem -LiteralPath $targetDir -Filter '*.patch' -File | Sort-Object Name)

    $identical = $source.Count -eq $existing.Count
    if ($identical) {
        for ($i = 0; $i -lt $source.Count; $i++) {
            if ($source[$i].Name -ne $existing[$i].Name) { $identical = $false; break }
            $a = Get-FileHash -LiteralPath $source[$i].FullName -Algorithm SHA256
            $b = Get-FileHash -LiteralPath $existing[$i].FullName -Algorithm SHA256
            if ($a.Hash -ne $b.Hash) { $identical = $false; break }
        }
    }

    if ($identical) {
        Write-Host "patches/$OldVersion already holds an identical snapshot. Nothing to do." -ForegroundColor Yellow
        exit 0
    }

    Write-Host "patches/$OldVersion already exists and differs from patches/latest." -ForegroundColor Red
    Write-Host "Refusing to overwrite a frozen patch set." -ForegroundColor Red
    exit 1
}

New-Item -ItemType Directory -Path $targetDir | Out-Null
Get-ChildItem -LiteralPath $LatestDir -Filter '*.patch' -File | Sort-Object Name | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $targetDir $_.Name)
}

Write-Host "Snapshotted $(@(Get-ChildItem -LiteralPath $targetDir -Filter '*.patch' -File).Count) patches into patches/$OldVersion." -ForegroundColor Green
