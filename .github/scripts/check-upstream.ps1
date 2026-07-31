#!/usr/bin/env pwsh
#Requires -Version 7

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$ISSUE_LABEL = "upstream-release"
$UPSTREAM_NEWS_URL = "https://www.nano-editor.org/dist/latest/NEWS"

function Get-LatestUpstreamNanoVersion {
    try {
        $data = Invoke-RestMethod -Uri $UPSTREAM_NEWS_URL
    } catch {
        Write-Host "Failed to fetch NEWS file from GNU nano website." -ForegroundColor Red
        exit 1
    }

    $match = [regex]::Match($data, '(\d{4}.\d{2}.\d{2}) - GNU nano ([\d.]+)')
    if (-not $match.Success) {
        Write-Host "Failed to parse NEWS file for latest nano version." -ForegroundColor Red
        exit 1
    }

    $latestDate = $match.Groups[1].Value
    $latestVersion = $match.Groups[2].Value
    Write-Debug "Latest upstream nano release date: $latestDate"
    Write-Debug "Latest upstream nano version: $latestVersion"
    return $latestVersion
}

function Get-GitHubLatestReleaseVersion {
    if (-not (Get-Command 'gh' -ErrorAction SilentlyContinue)) {
        Write-Host "GitHub CLI (gh) is not installed." -ForegroundColor Red
        exit 1
    }

    $tag = $(gh release list --json tagName,isLatest --jq '.[] | select(.isLatest) | .tagName') -replace '^v', ''
    return $tag
}

function Test-IssueExistsForVersion {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $issues = gh issue list --label $ISSUE_LABEL --state open --json title | ConvertFrom-Json
    foreach ($issue in $issues) {
        if ($issue.title -match [regex]::Escape($Version)) {
            return $true
        }
    }
    return $false
}

function New-UpstreamReleaseIssue {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Version,
        [Parameter(Mandatory = $true)]
        [string]$GitHubVersion
    )

    $title = "GNU nano $Version released upstream"
    $body = @"
GNU nano **$Version** has been released on [nano-editor.org]($UPSTREAM_NEWS_URL).

The current latest GitHub release **$GitHubVersion** is outdated. Please update the conda recipe and trigger a new release.

- Upstream NEWS: https://www.nano-editor.org/news.php
- Diff: https://github.com/ahjragaas/nano/compare/v$GitHubVersion...v$Version
"@

    if ($env:CI) {
        gh issue create --title $title --label $ISSUE_LABEL --body $body
        Write-Host "Created issue: $title" -ForegroundColor Green
    } else {
        Write-Host "Dry run: issue would be created:" -ForegroundColor Gray
        Write-Host "  Title: $title" -ForegroundColor Gray
        Write-Host "  Label: $ISSUE_LABEL" -ForegroundColor Gray
        Write-Host "  Body:" -ForegroundColor Gray
        Write-Host $body -ForegroundColor Gray
    }
}

## Main
Write-Host "Checking for upstream GNU nano releases..." -ForegroundColor Cyan

$upstreamVersion = Get-LatestUpstreamNanoVersion
$githubVersion = Get-GitHubLatestReleaseVersion
$cleanGitHubVersion = $githubVersion -replace '^v(.*?)(:?-.*)$', '$1'

Write-Host "Upstream version: $upstreamVersion" -ForegroundColor Cyan
Write-Host "GitHub version:   $githubVersion" -ForegroundColor Cyan

if (-not $githubVersion) {
    Write-Host "No GitHub release found. Skipping." -ForegroundColor Yellow
    exit 0
}

if ([version]$upstreamVersion -le [version]$cleanGitHubVersion) {
    Write-Host "GitHub release is up to date." -ForegroundColor Green
    exit 0
}

Write-Host "Upstream version $upstreamVersion is newer than GitHub release $githubVersion." -ForegroundColor Yellow

if (Test-IssueExistsForVersion -Version $upstreamVersion) {
    Write-Host "An open issue for version $upstreamVersion already exists. Skipping." -ForegroundColor Yellow
    exit 0
}

Write-Host "Creating issue for upstream release $upstreamVersion..." -ForegroundColor Cyan
New-UpstreamReleaseIssue -Version $upstreamVersion -GitHubVersion $cleanGitHubVersion
