#!/usr/bin/env pwsh
#Requires -Version 7

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$CACHE_DIR = "$PSScriptRoot/../../.cache"
$REUPLOAD_PLATFORMS = @('win-64', 'win-arm64')

function Get-NanoCondaLatestReleases {
    if (-not (Get-Command 'pixi' -ErrorAction SilentlyContinue)) {
        Write-Host "Pixi is not installed." -ForegroundColor Red
        exit 1
    }

    # To make pixi search all platforms
    $fakeManifestPath = "$CACHE_DIR/pixi.toml"
    $fakeManifest = @"
[workspace]
name = "fake"
channels = ["chawyehsu", "conda-forge"]
platforms = ["win-64", "win-arm64", "win-32"]
"@
    if (Test-Path $fakeManifestPath) {
        Remove-Item $fakeManifestPath -Force
    }
    New-Item -ItemType File -Path $fakeManifestPath -Value $fakeManifest -Force | Out-Null

    $json = $(pixi search nano -c chawyehsu --json --manifest-path $fakeManifestPath) | ConvertFrom-Json
    $latestReleases = @()

    foreach ($platform in $REUPLOAD_PLATFORMS) {
        if (-not ($json.PSObject.Properties.Name -contains $platform) -or $json.$platform.Count -eq 0) {
            Write-Host "No packages found for platform '$platform'" -ForegroundColor Yellow
            continue
        }

        $latest = $json.$platform |
            Sort-Object `
                @{Expression = {[version]$_.version}; Descending = $true},
                @{Expression = {$_.timestamp}; Descending = $true} |
            Select-Object -First 1

        Add-Member -InputObject $latest -NotePropertyName conda_version -NotePropertyValue $(
            if ($latest.build_number -ne '0') {
                "$($latest.version)-$($latest.build_number)"
            } else {
                $latest.version
            }
        )

        $latestReleases += $latest
    }

    return $latestReleases
}

function Get-NanoGitHubLatestRelease {
    if (-not (Get-Command 'gh' -ErrorAction SilentlyContinue)) {
        Write-Host "GitHub CLI (gh) is not installed." -ForegroundColor Red
        exit 1
    }

    $tag = $(gh release list --json tagName,isLatest --jq '.[] | select(.isLatest) | .tagName') -replace '^v', ''
    return $tag
}

function Resolve-PathWithReparseCheck {
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    $resolvedParts = @()
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $parts = $fullPath -split '[\\/]' | Where-Object { $_ -ne '' }

    # Drive letter (parts[0]) on Windows or root slash on Unix
    $current = if ($IsWindows) { $parts[0] } else { [System.IO.Path]::DirectorySeparatorChar }
    $resolvedParts += $current

    # 1 for Windows to skip drive letter
    $i = if ($IsWindows) { 1 } else { 0 }
    for (; $i -lt $parts.Length; $i++) {
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
                $current = $resolvedParts -join [System.IO.Path]::DirectorySeparatorChar
                continue
            }
        }

        $resolvedParts += $parts[$i]
    }

    $resolvedPath = if ($IsWindows) {
        $resolvedParts -join [System.IO.Path]::DirectorySeparatorChar
    } else {
        $paths = $resolvedParts[1..$resolvedParts.Length]
        '/' + ($paths -join [System.IO.Path]::DirectorySeparatorChar)
    }

    return [PSCustomObject]@{
        OriginalPath = $fullPath
        ResolvedPath = $resolvedPath
    }
}

function Invoke-ExtractCondaPayload {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$CondaPath,
        [Parameter(Mandatory = $true)]
        [string]$OutputDir
    )

    if (Test-Path -LiteralPath $OutputDir) {
        Remove-Item -LiteralPath $OutputDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

    & tar -xf $CondaPath.FullName -C $OutputDir | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract .conda archive: $($CondaPath.Name)"
    }

    $payloadCandidates = @(Get-ChildItem -LiteralPath $OutputDir -Filter 'pkg-*.tar.zst' -File)
    if ($payloadCandidates.Count -ne 1) {
        throw "Expected exactly one pkg-*.tar.zst in $($CondaPath.Name), found $($payloadCandidates.Count)"
    }

    return $payloadCandidates[0]
}

function Expand-PkgTarZst {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$TarZstPath,
        [Parameter(Mandatory = $true)]
        [string]$OutputDir
    )

    if (Test-Path -LiteralPath $OutputDir) {
        Remove-Item -LiteralPath $OutputDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

    $packageDir = Join-Path $OutputDir 'package'
    New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

    & tar -xf $TarZstPath.FullName -C $packageDir | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to extract payload tar.zst: $($TarZstPath.Name)"
    }

    $extractedEntries = @(Get-ChildItem -LiteralPath $packageDir -Force)
    if ($extractedEntries.Count -eq 0) {
        throw "No files were extracted from payload: $($TarZstPath.Name)"
    }

    return $packageDir
}

function Invoke-RepackToZip {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDir,
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$ZipPath
    )

    if (Test-Path -LiteralPath $ZipPath.FullName) {
        Remove-Item -LiteralPath $ZipPath.FullName -Force
    }

    $entries = @(Get-ChildItem -LiteralPath $SourceDir -Force | Select-Object -ExpandProperty Name)
    if ($entries.Count -eq 0) {
        throw "Source directory is empty, cannot create zip archive: $SourceDir"
    }

    & tar -a -cf $ZipPath.FullName -C $SourceDir @entries | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create zip archive: $($ZipPath.Name)"
    }

    if (-not (Test-Path -LiteralPath $ZipPath.FullName)) {
        throw "Zip archive was not created: $($ZipPath.Name)"
    }

    return $ZipPath
}

function Convert-CondaAssetToZip {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$CondaPath
    )

    # resparse resolve
    $CondaPath = [System.IO.FileInfo](Resolve-PathWithReparseCheck -Path $CondaPath.FullName).ResolvedPath

    $workDir = Join-Path $CACHE_DIR ("extract-" + [System.Guid]::NewGuid().ToString('N'))
    $workDir = (Resolve-PathWithReparseCheck -Path $workDir).ResolvedPath

    $condaExtractDir = Join-Path $workDir 'conda'
    $payloadExtractDir = Join-Path $workDir 'payload'
    $zipPath = [System.IO.FileInfo]([System.IO.Path]::ChangeExtension($CondaPath.FullName, '.zip'))

    try {
        New-Item -ItemType Directory -Path $workDir -Force | Out-Null

        Write-Host "Extracting conda package: $($CondaPath.Name)" -ForegroundColor Cyan
        $tarZstPath = Invoke-ExtractCondaPayload -CondaPath $CondaPath -OutputDir $condaExtractDir

        Write-Host "Extracting payload tar.zst: $($tarZstPath.Name)" -ForegroundColor Cyan
        $packageDir = Expand-PkgTarZst -TarZstPath $tarZstPath -OutputDir $payloadExtractDir

        Write-Host "Repacking to zip: $($zipPath.Name)" -ForegroundColor Cyan
        return Invoke-RepackToZip -SourceDir $packageDir -ZipPath $zipPath
    } finally {
        if (Test-Path -LiteralPath $workDir) {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

## Main script logic
if (-not (Get-Command 'tar' -ErrorAction SilentlyContinue)) {
    Write-Host "tar command is not available." -ForegroundColor Red
    exit 1
}

Write-Host "Fetching latest nano version... ($($REUPLOAD_PLATFORMS -join ','))" -ForegroundColor Cyan
$CondaReleases = Get-NanoCondaLatestReleases
$GitHubVersion = Get-NanoGitHubLatestRelease

$CondaPlatforms = $CondaReleases | Select-Object -ExpandProperty subdir -Unique
$CondaVersion = $CondaReleases | Select-Object -ExpandProperty conda_version -Unique

if ($CondaVersion.Count -ne 1) {
    Write-Host "Latest package versions across platforms are inconsistent:" -ForegroundColor Red
    $CondaReleases | ForEach-Object {
        Write-Host "  $($_.subdir): $($_.conda_version)" -ForegroundColor Red
    }
    exit 1
}

if ($GitHubVersion) {
    if ($GitHubVersion -ne $CondaVersion) {
        Write-Host "Latest version on Anaconda ($($CondaPlatforms -join ',')): $CondaVersion" -ForegroundColor Yellow
        Write-Host "Latest version on GitHub: $GitHubVersion" -ForegroundColor Yellow
    } else {
        Write-Host "Latest version already on GitHub: $GitHubVersion" -ForegroundColor Green
        exit 0
    }
}

Write-Host "Releasing new version to GitHub..." -ForegroundColor Magenta
if (-not (Test-Path $CACHE_DIR)) {
    New-Item -ItemType Directory -Path $CACHE_DIR | Out-Null
}

$assetPaths = @()

foreach ($CondaRelease in $CondaReleases) {
    $assetPath = "$CACHE_DIR/nano-$($CondaRelease.conda_version)-$($CondaRelease.subdir).conda"

    if (Test-Path $assetPath) {
        Remove-Item $assetPath -Force
    }

    try {
        Write-Host "Downloading nano package from Anaconda ($($CondaRelease.subdir)): $($CondaRelease.url)" -ForegroundColor Cyan
        Invoke-WebRequest -Uri $CondaRelease.url -OutFile $assetPath
        $assetPaths += (Resolve-PathWithReparseCheck -Path (Resolve-Path $assetPath)).ResolvedPath
    } catch {
        Write-Host "Failed to download nano package for $($CondaRelease.subdir) from Anaconda" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
}

if ($assetPaths.Count -eq $REUPLOAD_PLATFORMS.Count) {
    $zipPaths = @()

    foreach ($ap in $assetPaths) {
        $condaPath = [System.IO.FileInfo]$ap
        try {
            $zipPath = Convert-CondaAssetToZip -CondaPath $condaPath
            $zipPaths += Resolve-Path $zipPath
        } catch {
            Write-Host "Failed to convert package to zip: $($condaPath.Name)" -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Red
            exit 1
        }
    }

    $allAssetPaths = @($assetPaths + $zipPaths)
    $expectedAssetCount = $REUPLOAD_PLATFORMS.Count * 2
    if ($allAssetPaths.Count -ne $expectedAssetCount) {
        Write-Host "Unexpected asset count after repack. Expected: $expectedAssetCount, Actual: $($allAssetPaths.Count)" -ForegroundColor Red
        exit 1
    }

    $releaseTag = "v$($CondaVersion)"

    try {
        $json = $(gh release view $releaseTag --json tagName 2>$null) | ConvertFrom-Json
        if ($null -ne $json) {
            Write-Host "Release $releaseTag already exists on GitHub" -ForegroundColor Green
            exit 0
        }
    } catch {
        Write-Host "Failed to check existing GitHub releases" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }

    if ($env:CI) {
        Write-Host "Creating GitHub release $releaseTag with assets..." -ForegroundColor Cyan
        try {
            gh release create $releaseTag @allAssetPaths --latest --title $releaseTag --notes "GNU nano v$($CondaVersion) for Windows"
            Write-Host "Release v$CondaVersion created successfully." -ForegroundColor Green
        } catch {
            Write-Host "Failed to create GitHub release" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "Dry run: GitHub release $releaseTag would be created with assets:" -ForegroundColor Gray
        $allAssetPaths | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    }
} else {
    Write-Host "Not all assets were downloaded successfully. Expected: $($REUPLOAD_PLATFORMS.Count), Downloaded: $($assetPaths.Count)" -ForegroundColor Red
    exit 1
}
