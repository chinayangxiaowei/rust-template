# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#Requires -Version 7.0

<#
.SYNOPSIS
    Replaces the template's upstream identity with this project's own.

.DESCRIPTION
    Reads rebrand.psd1 (see the comments there) and rewrites every tracked text
    file except excluded paths and files or regions owned by cargo anvil.

    By default only lists the changes. -Apply writes them. -Check lists lines
    that still carry the upstream identity and exits 1 if there are any.

.EXAMPLE
    ./scripts/rebrand.ps1
    ./scripts/rebrand.ps1 -Apply
    ./scripts/rebrand.ps1 -Check
#>
[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$RepoRoot,
    [switch]$Apply,
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib' 'rebrand.ps1')

if (-not $RepoRoot) { $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
if (-not $ConfigPath) { $ConfigPath = Join-Path $RepoRoot 'rebrand.psd1' }
$config = Resolve-RebrandConfig (Import-PowerShellDataFile -LiteralPath $ConfigPath)

if ($Check) {
    $residue = @(Find-RebrandResidue -RepoRoot $RepoRoot -Config $config)
    foreach ($item in $residue) { Write-Host "$($item.Path):$($item.Line): $($item.Text)" }
    if ($residue.Count -gt 0) {
        Write-Host "rebrand: $($residue.Count) line(s) still carry the upstream identity. Add a rule, an Exclude entry or an Allow pattern in rebrand.psd1."
        exit 1
    }
    Write-Host 'rebrand: no upstream identity left.'
    exit 0
}

$changes = @(Invoke-Rebrand -RepoRoot $RepoRoot -Config $config -Apply:$Apply)
foreach ($change in $changes) {
    $from = $change.From -replace "`n", '\n'
    $to = $change.To -replace "`n", '\n'
    Write-Host "$($change.Path):$($change.Line): '$from' -> '$to'"
}
$files = @($changes | ForEach-Object Path | Sort-Object -Unique).Count
if ($Apply) {
    Write-Host "rebrand: applied $($changes.Count) change(s) in $files file(s)."
} else {
    Write-Host "rebrand: $($changes.Count) change(s) in $files file(s). Run 'just rebrand apply' to write them."
}
