#!/usr/bin/env pwsh

$ErrorActionPreference = "Stop"
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
    New-Item -ItemType File -Path $fakeManifestPath -Value $fakeManifest | Out-Null

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
    $fileName = (Split-Path $CondaRelease.url -Leaf) -replace '.conda', "-$($CondaRelease.subdir).conda"
    $assetPath = "$CACHE_DIR/$fileName"

    if (Test-Path $assetPath) {
        Remove-Item $assetPath -Force
    }

    try {
        Write-Host "Downloading nano package from Anaconda ($($CondaRelease.subdir)): $($CondaRelease.url)" -ForegroundColor Cyan
        Invoke-WebRequest -Uri $CondaRelease.url -OutFile $assetPath
        $assetPaths += $assetPath
    } catch {
        Write-Host "Failed to download nano package for $($CondaRelease.subdir) from Anaconda" -ForegroundColor Red
        exit 1
    }
}

if ($assetPaths.Count -eq $REUPLOAD_PLATFORMS.Count) {
    try {
        $releaseTag = "v$($CondaVersion)"
        $releaseExists = $null -ne $(gh release view $releaseTag --json tagName 2>$null)

        if ($releaseExists) {
            Write-Host "Release $releaseTag already exists on GitHub" -ForegroundColor Green
            exit 0
        } else {
            if ($env:CI) {
                $paths = $assetPaths -join ' '
                gh release create $releaseTag $paths --latest --title $releaseTag --notes "GNU nano v$($CondaVersion) for Windows"
            }
        }
        Write-Host "Release v$CondaVersion created successfully." -ForegroundColor Green
    } catch {
        Write-Host "Failed to create GitHub release" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Not all assets were downloaded successfully. Expected: $($REUPLOAD_PLATFORMS.Count), Downloaded: $($assetPaths.Count)" -ForegroundColor Red
    exit 1
}
