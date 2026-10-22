#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Set up the working directory for building GNU nano on Windows.
.DESCRIPTION
    This script sets up the necessary environment and dependencies for
    building GNU nano on Windows.
.PARAMETER NanoVersion
    Specifies the version of GNU nano to set up.
    If not specified, the latest version will be used.
#>
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$NanoVersion
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot/../.agents/skills/renew-patches/scripts/common.ps1"

function Get-LatestNanoRelease {
    try {
        $data = Invoke-RestMethod -Uri $script:UpstreamNewsUrl
    } catch {
        Write-Host "Failed to fetch NEWS file from GNU nano repository." -ForegroundColor Red
        exit 1
    }

    $match = [regex]::Match($data, '(\d{4}.\d{2}.\d{2}) - GNU nano ([\d.]+)')
    if (-not $match.Success) {
        Write-Host "Failed to parse NEWS file for latest nano version." -ForegroundColor Red
        exit 1
    }

    $latestDate = $match.Groups[1].Value
    $latestVersion = $match.Groups[2].Value
    Write-Debug "Latest nano release date: $latestDate"
    Write-Debug "Latest nano version: $latestVersion"
    return $latestVersion
}

function Invoke-NewWorkingCopy {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$NanoVersion,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TarballPath
    )

    if (-not [boolean](Get-Command 'jj' -ErrorAction SilentlyContinue)) {
        Write-Host "Required 'jj' command not found." -ForegroundColor Red
        exit 1
    }
    if (-not [boolean](Get-Command 'git' -ErrorAction SilentlyContinue)) {
        Write-Host "Required 'git' command not found." -ForegroundColor Red
        exit 1
    }

    & jj new main
    & jj restore
    # for `./configure` file
    & jj config set --repo snapshot.max-new-file-size 1999999

    Expand-NanoTarball -TarballPath $TarballPath -Destination "$PSScriptRoot/.."

    # Commit the nano source
    & jj describe -m "nano: v$NanoVersion"
    & jj bookmark set "v$NanoVersion"
    & jj new
    # Update gitignore
    Copy-Item -Path "$PSScriptRoot/gitignore.tpl" -Destination "$PSScriptRoot/../.gitignore" -Force
    & jj describe -m "chore: update gitignore"
    & jj new

    # Apply patches
    $_PatchesRoot = $script:PatchesRoot
    $PatchesPath = $null

    if (Test-Path "$_PatchesRoot/$NanoVersion") {
        $PatchesPath = "$_PatchesRoot/$NanoVersion"
    } elseif (Test-Path "$_PatchesRoot/latest") {
        $PatchesPath = "$_PatchesRoot/latest"

        $newestSet = Get-NewestPatchSetVersion
        if ($null -ne $newestSet -and $newestSet -ne $NanoVersion) {
            Write-Host "Warning: patches/latest is being applied to '$NanoVersion', but the newest frozen patch set is '$newestSet'." -ForegroundColor Yellow
            Write-Host "patches/latest may not have been renewed for this release yet." -ForegroundColor Yellow
        }
    }

    if ($PatchesPath) {
        $result = Invoke-GitAmPatches -PatchesDir $PatchesPath
        if ($result.Failed.Count -gt 0) {
            Write-Host "Failed to apply patch: $($result.Failed[-1])" -ForegroundColor Red
            exit 1
        }
    }

    Write-Host "New working copy set up with GNU nano version $NanoVersion." -ForegroundColor Green
}

function Invoke-SetupWorkingDir {
    if (-not $NanoVersion) {
        $NanoVersion = Get-LatestNanoRelease
    }

    $TarballPath = Get-NanoReleaseTarball -Version $NanoVersion
    Invoke-NewWorkingCopy -NanoVersion $NanoVersion -TarballPath $TarballPath
}

if (($PSVersionTable.PSVersion.Major) -gt 5) {
    if (-not $IsWindows) {
        Write-Error "This script is intended to run on Windows only."
        exit 1
    }
}

Invoke-SetupWorkingDir
