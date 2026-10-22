#!/usr/bin/env pwsh
# Shared helpers for the patch toolchain. Dot-source this file; never run it.

$script:PatchToolsRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
$script:CacheDir = Join-Path $script:PatchToolsRoot ".cache"
$script:PatchesRoot = Join-Path $script:PatchToolsRoot "patches"
$script:UpstreamNewsUrl = "https://www.nano-editor.org/dist/latest/NEWS"

function Get-NanoReleaseTarball {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Version
    )

    $majorVersion = $Version.Split('.')[0]

    $url = "https://www.nano-editor.org/dist/v$majorVersion/nano-$Version.tar.xz"
    $outputPath = "$script:CacheDir/nano-$Version.tar.xz"

    if (Test-Path $outputPath) {
        Write-Host "Nano tarball for version $Version already cached."
        return $outputPath
    }

    try {
        Write-Host "Downloading GNU nano version $Version from $url..."
        if (-not (Test-Path $script:CacheDir)) {
            New-Item -ItemType Directory -Path $script:CacheDir | Out-Null
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

    $current = if ($IsWindows) { $parts[0] } else { [System.IO.Path]::DirectorySeparatorChar }
    $resolvedParts += $current

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

function Expand-NanoTarball {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$TarballPath,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Destination
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
        $resolved = Resolve-PathWithReparseCheck -Path $Destination
        & tar -xf $TarballPath -C $resolved.ResolvedPath --strip-components=1
        if ($LASTEXITCODE -ne 0) {
            throw "tar exited with $LASTEXITCODE"
        }
        Write-Host "Extracted tarball"
    } catch {
        Write-Host "Failed to extract tarball." -ForegroundColor Red
        exit 1
    }
}

function Invoke-GitAmPatches {
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$PatchesDir
    )

    $patchFiles = @(Get-ChildItem -LiteralPath $PatchesDir -Filter '*.patch' -File | Sort-Object Name)
    if ($patchFiles.Count -eq 0) {
        Write-Host "No patches found in $PatchesDir." -ForegroundColor Red
        exit 1
    }

    $failed = @()
    foreach ($patch in $patchFiles) {
        Write-Host "Applying patch: $($patch.Name)" -ForegroundColor DarkGray
        & git am --reject --whitespace=nowarn $patch.FullName
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Failed to apply patch: $($patch.Name)" -ForegroundColor Red
            $failed += $patch.Name
            # Leave the working copy at the failure so .rej files are inspectable.
            return [PSCustomObject]@{
                Failed = $failed
                Applied = $patchFiles.Count - 1
            }
        }
    }

    return [PSCustomObject]@{
        Failed = @()
        Applied = $patchFiles.Count
    }
}

function Get-NewestPatchSetVersion {
    # The highest versioned directory under patches/. `latest` is excluded: it
    # carries no version of its own, which is exactly why this is derived from
    # the snapshots rather than from a stored marker.
    $versions = @(Get-ChildItem -LiteralPath $script:PatchesRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+(\.\d+)+$' } |
        ForEach-Object { $_.Name })

    if ($versions.Count -eq 0) {
        return $null
    }

    return ($versions | Sort-Object { [version]$_ } -Descending | Select-Object -First 1)
}
