#!/usr/bin/env pwsh

<#
.SYNOPSIS
    compile_commands.json patcher
.DESCRIPTION
    This script patches the compile_commands.json file to ensure that
    the include paths for the conda environment are correctly set up
    for building GNU nano on Windows.
#>

$CompileCommandsJSON = "$PSScriptRoot/../compile_commands.json"

if (Test-Path $CompileCommandsJSON) {
    $regexInclude = '(?m)^((\s+)"-I((?:(?!Library).)*)/include",)$\r?\n(?:(?!Library).)*$'

    $Content = Get-Content -Raw -Path $CompileCommandsJSON

    $Content -match $regexInclude | Out-Null
    if ($Script:Matches.Count -gt 0) {
        # Write-Host $Script:Matches[0]
        $original = $Script:Matches[1]
        $space = $Script:Matches[2]
        $path = $Script:Matches[3]
        # Write-Host "Original: $original"
        # Write-Host "Space: '$space'"
        # Write-Host "Path: '$path'"
        $Content = $Content -replace $original, `
            "${original}`n${space}`"-I${path}/Library/include`","

        # Write-Host "Modified content:"
        # Write-Host $Content
    
        Set-Content -Path $CompileCommandsJSON -Value $Content -NoNewline
        Write-Host "Patched compile_commands.json."
    } else {
        Write-Host "Already patched compile_commands.json."
    }
}
