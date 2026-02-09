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
$CACHE_DIR = "$PSScriptRoot/../.cache"

function Get-LatestNanoRelease {
    $url = "https://cgit.git.savannah.gnu.org/cgit/nano.git/plain/NEWS"
    try {
        $data = Invoke-WebRequest -Uri $url
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

function Get-NanoReleaseTarball {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Version
    )

    $majorVersion = $Version.Split('.')[0]

    $url = "https://www.nano-editor.org/dist/v$majorVersion/nano-$Version.tar.xz"
    $outputPath = "$CACHE_DIR/nano-$Version.tar.xz"

    if (Test-Path $outputPath) {
        Write-Host "Nano tarball for version $Version already cached."
        return $outputPath
    }

    try {
        Write-Host "Downloading GNU nano version $Version from $url..."
        if (-not (Test-Path $CACHE_DIR)) {
            New-Item -ItemType Directory -Path $CACHE_DIR | Out-Null
        }
        Invoke-WebRequest -Uri $url -OutFile $outputPath
        Write-Host "Downloaded nano tarball to $outputPath"
    } catch {
        Write-Host "Failed to download nano tarball from $url." -ForegroundColor Red
        exit 1
    }

    return $outputPath
}

function Resolve-PathWithReparseCheck {
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolvedParts = @()
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $parts = $fullPath -split '[\\/]' | Where-Object { $_ -ne '' }

    # Drive letter
    $current = $parts[0]
    $resolvedParts += $current

    for ($i = 1; $i -lt $parts.Length; $i++) {
        $current = Join-Path $current $parts[$i]

        if (-not (Test-Path -LiteralPath $current)) {
            $resolvedParts += $parts[$i..($parts.Length - 1)]
            break
        }

        $item = Get-Item -LiteralPath $current -Force

        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            if ($item.Target) {
                $targetPath = $item.Target

                if (-not [System.IO.Path]::IsPathRooted($targetPath)) {
                    $targetPath = Join-Path $item.DirectoryName $targetPath
                }

                $current = [System.IO.Path]::GetFullPath($targetPath)

                $resolvedParts = $current -split '[\\/]' | Where-Object { $_ -ne '' }
                $current = $resolvedParts -join '\'
                continue
            }
        }

        $resolvedParts += $parts[$i]
    }

    return [PSCustomObject]@{
        OriginalPath = $fullPath
        ResolvedPath = ($resolvedParts -join '\')
    }
}

function Invoke-ExtractTarball {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TarballPath
    )

    if (-not (Test-Path $TarballPath)) {
        Write-Host "Tarball not found at $TarballPath." -ForegroundColor Red
        exit 1
    }

    if (-not [boolean](Get-Command 'tar' -ErrorAction SilentlyContinue)) {
        Write-Host "Required 'tar' command not found." -ForegroundColor Red
        exit 1
    }

    try {
        # tar cannot handle reparse points, so we need to resolve the path first
        $TargetDir = Resolve-PathWithReparseCheck -Path "$PSScriptRoot/.."
        tar -xf $TarballPath -C $TargetDir.ResolvedPath --strip-components=1
        Write-Host "Extracted tarball"
    } catch {
        Write-Host "Failed to extract tarball." -ForegroundColor Red
        exit 1
    }
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

    Invoke-ExtractTarball -TarballPath $TarballPath

    # Commit the nano source
    & jj describe -m "nano: v$NanoVersion"
    & jj new
    # Update gitignore
    Copy-Item -Path "$PSScriptRoot/gitignore.tpl" -Destination "$PSScriptRoot/../.gitignore" -Force
    & jj describe -m "chore: update gitignore"
    & jj new

    # Apply patches
    $_PatchesRoot = "$PSScriptRoot/../patches"
    $PatchesPath = $null
    
    if (Test-Path "$_PatchesRoot/$NanoVersion") {
        $PatchesPath = "$_PatchesRoot/$NanoVersion/*.patch"
    } elseif (Test-Path "$_PatchesRoot/latest/*.patch") {
        $PatchesPath = "$_PatchesRoot/latest/*.patch"
    }

    if ($PatchesPath) {
        Get-ChildItem -Path "$PatchesPath" | Sort-Object Name | ForEach-Object {
            Write-Host "Applying patch: $($_.Name)" -ForegroundColor DarkGray
            & git am --reject --whitespace=nowarn $_.FullName
            if ($LASTEXITCODE -ne 0) {
                Write-Host "Failed to apply patch: $($_.Name)" -ForegroundColor Red
                exit 1
            }
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
