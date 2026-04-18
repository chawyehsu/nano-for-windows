#!/usr/bin/env pwsh

$CACHE_DIR = "$PSScriptRoot/../../.cache"

function Get-NanoCondaLatestRelease {
    if (-not (Get-Command 'pixi' -ErrorAction SilentlyContinue)) {
        Write-Host "Pixi is not installed." -ForegroundColor Red
        exit 1
    }

    $json = $(pixi search nano -c chawyehsu --json) | ConvertFrom-Json
    if (-not($json."win-64" -and $json."win-64".Count -gt 0)) {
        Write-Host "No win-64 packages found for nano." -ForegroundColor Red
        exit 1
    }

    $latest = $json."win-64" |
        Sort-Object `
            @{Expression = {[version]$_.version}; Descending = $true},
            @{Expression = {$_.timestamp}; Descending = $true} |
        Select-Object -First 1
    return $latest
}

function Get-NanoGitHubLatestRelease {
    if (-not (Get-Command 'gh' -ErrorAction SilentlyContinue)) {
        Write-Host "GitHub CLI (gh) is not installed." -ForegroundColor Red
        exit 1
    }

    $tag = $(gh release list --json tagName,isLatest --jq '.[] | select(.isLatest) | .tagName') -replace '^v', ''
    return $tag
}

Write-Host "Fetching latest nano version..." -ForegroundColor Cyan
$CondaRelease = Get-NanoCondaLatestRelease
$GitHubVersion = Get-NanoGitHubLatestRelease
$CondaVersion = if ($CondaRelease.build_number -ne '0') {
    "$($CondaRelease.version)-$($CondaRelease.build_number)"
} else {
    $CondaRelease.version
}

if ($GitHubVersion) {
    if ($GitHubVersion -ne $CondaVersion) {
        Write-Host "Latest version on Anaconda: $($CondaRelease.version)" -ForegroundColor Yellow
        Write-Host "Latest version on GitHub: $GitHubVersion" -ForegroundColor Yellow
    } else {
        Write-Host "Latest version already on GitHub: $GitHubVersion" -ForegroundColor Green
        exit 0
    }
}

Write-Host "Pushing new release to GitHub..." -ForegroundColor Cyan
$fileName = Split-Path $CondaRelease.url -Leaf
if (-not (Test-Path $CACHE_DIR)) {
    New-Item -ItemType Directory -Path $CACHE_DIR | Out-Null
}
if (Test-Path "$CACHE_DIR/$fileName") {
    Remove-Item "$CACHE_DIR/$fileName" -Force
}

try {
    Write-Host "Downloading nano package from Anaconda: $($CondaRelease.url)" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $CondaRelease.url -OutFile "$CACHE_DIR/$fileName"
} catch {
    Write-Host "Failed to download nano package from Anaconda" -ForegroundColor Red
    exit 1
}

if (Test-Path "$CACHE_DIR/$fileName") {
    if ($env:CI) {
        gh release create "v$($CondaVersion)" "$CACHE_DIR/$fileName" --latest --title "v$($CondaVersion)" --notes "GNU nano v$($CondaVersion) for Windows"
    }
    Write-Host "Release v$CondaVersion created successfully." -ForegroundColor Green
}
