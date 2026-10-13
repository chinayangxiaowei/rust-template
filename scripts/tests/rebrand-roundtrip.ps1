# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#Requires -Version 7.0

<#
.SYNOPSIS
    Checks that a rebranded copy of this repository stays rebranded.

.DESCRIPTION
    Copies the working tree to a temporary git repository, applies
    rebrand.psd1, then runs every tool that generates or rewrites files and
    checks that none of them brings the upstream identity back or breaks:

      1. rebrand check finds no upstream identity, and a second apply is a no-op;
      2. anvil-owned files and anvil-managed regions are byte-identical;
      3. `cargo anvil --dry-run` reports nothing to regenerate;
      4. cargo-heather accepts every license header;
      5. cargo-doc2readme regenerates crate READMEs identical to the rebranded ones;
      6. the Pester suite fails no test that passes before the rebrand;
      7. add-crate.ps1 creates a crate from the rebranded template;
      8. rebrand check still passes after all of the above.

    Needs cargo-anvil, cargo-heather and cargo-doc2readme on PATH.

.PARAMETER KeepCopy
    Leave the temporary copy in place for inspection.
#>
[CmdletBinding()]
param([switch]$KeepCopy)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
$copy = Join-Path ([System.IO.Path]::GetTempPath()) ("rebrand-roundtrip-" + [guid]::NewGuid().ToString('N'))
$failures = [System.Collections.Generic.List[string]]::new()

function Invoke-Step {
    param([string]$Name, [scriptblock]$Body)

    Write-Host "==> $Name"
    try {
        & $Body
        Write-Host "    ok"
    } catch {
        Write-Host "    FAILED: $($_.Exception.Message)"
        $failures.Add($Name)
    }
}

# Runs a native command in the copy and throws if it exits non-zero.
function Invoke-InCopy {
    param([string]$Command, [string[]]$Arguments, [string]$InputText)

    Push-Location $copy
    try {
        if ($PSBoundParameters.ContainsKey('InputText')) {
            $InputText | & $Command @Arguments
        } else {
            & $Command @Arguments
        }
        if ($LASTEXITCODE -ne 0) { throw "'$Command $($Arguments -join ' ')' exited with $LASTEXITCODE." }
    } finally {
        Pop-Location
    }
}

# Runs the Pester suite under $Root in a child process and returns the names of
# failed tests, blocks and containers.
function Get-PesterFailures {
    param([string]$Root)

    $out = Join-Path ([System.IO.Path]::GetTempPath()) ("rebrand-pester-" + [guid]::NewGuid().ToString('N') + '.txt')
    $runner = Join-Path $Root 'scripts' 'tests' 'Pester' 'Run-Tests.ps1'
    $command = "`$r = & '$runner' -PassThru; " +
        "@(`$r.Failed.ExpandedPath) + @(`$r.FailedBlocks.ExpandedPath) + @(`$r.FailedContainers.Item) | " +
        "Where-Object { `$_ } | ForEach-Object { `"`$_`".Replace('$Root', '<root>') } | Sort-Object -Unique | Set-Content '$out'"
    pwsh -NoProfile -Command $command | Out-Null
    try { return @(Get-Content $out -ErrorAction Stop) } finally { Remove-Item $out -ErrorAction SilentlyContinue }
}

try {
    Invoke-Step 'Copy the working tree to a temporary repository' {
        $files = @(git -C $repoRoot ls-files --cached --others --exclude-standard)
        foreach ($path in $files) {
            $source = Join-Path $repoRoot $path
            if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
            $target = Join-Path $copy $path
            New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $target
        }
        Invoke-InCopy git @('init', '--quiet')
        Invoke-InCopy git @('add', '-A')
        Invoke-InCopy git @('-c', 'user.name=rebrand', '-c', 'user.email=rebrand@example.com', 'commit', '--quiet', '-m', 'copy')
    }

    Invoke-Step 'rebrand apply' { Invoke-InCopy pwsh @('-NoProfile', '-File', 'scripts/rebrand.ps1', '-Apply') }

    Invoke-Step 'rebrand check finds no upstream identity' {
        Invoke-InCopy pwsh @('-NoProfile', '-File', 'scripts/rebrand.ps1', '-Check')
    }

    Invoke-Step 'a second rebrand apply changes nothing' {
        Invoke-InCopy git @('add', '-A')
        Invoke-InCopy pwsh @('-NoProfile', '-File', 'scripts/rebrand.ps1', '-Apply')
        # Staged = first apply; anything unstaged now came from the second one.
        $changed = @(git -C $copy diff --name-only)
        if ($changed.Count -gt 0) { throw "second apply modified: $($changed -join ', ')" }
    }

    Invoke-Step 'anvil-owned files and regions are byte-identical' {
        . (Join-Path $repoRoot 'scripts' 'lib' 'rebrand.ps1')
        $owned = Get-AnvilOwnedPaths -RepoRoot $copy
        foreach ($path in @(git -C $copy diff --cached --name-only HEAD)) {
            if ($path -in $owned) { throw "rebrand modified anvil-owned $path" }
            $before = @(Split-RebrandSegments -Text ((git -C $copy show "HEAD:$path") -join "`n") | Where-Object Managed)
            $after = @(Split-RebrandSegments -Text ((Get-Content (Join-Path $copy $path)) -join "`n") | Where-Object Managed)
            if ((($before | ForEach-Object Text) -join '') -ne (($after | ForEach-Object Text) -join '')) { throw "rebrand modified an anvil region in $path" }
        }
    }

    Invoke-Step 'cargo anvil reports nothing to regenerate' {
        Invoke-InCopy cargo @('anvil', '--dry-run', '--backend', 'github')
    }

    Invoke-Step 'cargo-heather accepts every license header' { Invoke-InCopy cargo @('heather') }

    Invoke-Step 'crate READMEs match cargo-doc2readme output' {
        $env:ANVIL_IMPACT = 'off'
        Invoke-InCopy just @('anvil-readme-check')
    }

    Invoke-Step 'the Pester suite fails no test that passes before the rebrand' {
        # Compare against the original tree rather than require a clean run:
        # the question is whether the rebrand broke anything, not whether the
        # suite was green beforehand.
        $before = Get-PesterFailures -Root $repoRoot
        $after = Get-PesterFailures -Root $copy
        $new = @($after | Where-Object { $_ -notin $before })
        Write-Host "    failing before: $($before.Count), after: $($after.Count)"
        if ($new.Count -gt 0) { throw "newly failing: $($new -join '; ')" }
    }

    Invoke-Step 'add-crate.ps1 creates a crate from the rebranded template' {
        $answers = "rebrand_probe`nProbe crate`nprobe`n`n"
        Invoke-InCopy pwsh @('-NoProfile', '-File', 'scripts/add-crate.ps1') -InputText $answers
        if (-not (Test-Path (Join-Path $copy 'crates' 'rebrand_probe' 'Cargo.toml'))) { throw 'crate was not created.' }
    }

    Invoke-Step 'rebrand check still passes after the generators ran' {
        Invoke-InCopy git @('add', '-A')
        Invoke-InCopy pwsh @('-NoProfile', '-File', 'scripts/rebrand.ps1', '-Check')
    }
} finally {
    if ($KeepCopy) {
        Write-Host "Copy kept at $copy"
    } else {
        Remove-Item -Recurse -Force $copy -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    Write-Host "rebrand round trip: $($failures.Count) step(s) failed: $($failures -join '; ')"
    exit 1
}
Write-Host 'rebrand round trip: all steps passed.'
