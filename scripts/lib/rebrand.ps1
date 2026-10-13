# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

# Library behind scripts/rebrand.ps1: replaces the template's upstream identity
# strings with a project's own, driven by rebrand.psd1. Files and regions that
# cargo anvil owns are never touched, so `cargo anvil` keeps seeing them as in sync.

Set-StrictMode -Version Latest

$script:RebrandConfigKeys = @('Values', 'Rules', 'Files', 'Exclude', 'Residue')
$script:AnvilRegionStart = '>>> anvil-managed:'
$script:AnvilRegionEnd = '<<< anvil-managed:'

# Expands ${name} placeholders from $Values. Throws on a name with no value.
function Expand-RebrandValue {
    param([string]$Text, [hashtable]$Values)

    return [regex]::Replace($Text, '\$\{([A-Za-z_][A-Za-z0-9_]*)\}', {
            param($match)
            $name = $match.Groups[1].Value
            if (-not $Values.ContainsKey($name)) {
                throw "rebrand: placeholder '`${$name}' has no entry in Values."
            }
            return [string]$Values[$name]
        })
}

# Validates a configuration loaded from rebrand.psd1 and expands its placeholders.
function Resolve-RebrandConfig {
    param([Parameter(Mandatory)][hashtable]$Raw)

    foreach ($key in $Raw.Keys) {
        if ($key -notin $script:RebrandConfigKeys) {
            throw "rebrand: unknown configuration key '$key'. Expected one of: $($script:RebrandConfigKeys -join ', ')."
        }
    }
    $values = if ($Raw.ContainsKey('Values')) { $Raw.Values } else { @{} }

    $rules = foreach ($rule in @($Raw['Rules'])) {
        if ($null -eq $rule) { continue }
        if ([string]::IsNullOrEmpty($rule.From)) {
            throw 'rebrand: every rule needs a non-empty From.'
        }
        [pscustomobject]@{
            From = ($rule.From -replace "`r`n", "`n")
            To   = Expand-RebrandValue -Text ([string]$rule.To) -Values $values
        }
    }
    $files = foreach ($file in @($Raw['Files'])) {
        if ($null -eq $file) { continue }
        [pscustomobject]@{
            Path    = $file.Path
            Content = Expand-RebrandValue -Text ([string]$file.Content -replace "`r`n", "`n") -Values $values
        }
    }
    $residue = if ($Raw.ContainsKey('Residue')) { $Raw.Residue } else { @{} }

    return [pscustomobject]@{
        Rules   = @($rules)
        Files   = @($files)
        Exclude = @($Raw['Exclude'] | Where-Object { $_ })
        Residue = [pscustomobject]@{
            Patterns = @($residue['Patterns'] | Where-Object { $_ })
            Allow    = @($residue['Allow'] | Where-Object { $_ })
        }
    }
}

# Returns the paths of whole files that cargo anvil owns, from .anvil.lock.
function Get-AnvilOwnedPaths {
    param([Parameter(Mandatory)][string]$RepoRoot)

    $lock = Join-Path $RepoRoot '.anvil.lock'
    if (-not (Test-Path $lock)) { return @() }

    $owned = [System.Collections.Generic.List[string]]::new()
    $inFile = $false
    foreach ($line in Get-Content $lock) {
        if ($line -match '^\s*\[\[(\w+)\]\]') { $inFile = $Matches[1] -eq 'file'; continue }
        if ($inFile -and $line -match '^\s*path\s*=\s*"([^"]+)"') { $owned.Add($Matches[1]) }
    }
    return $owned.ToArray()
}

# Converts a path glob (`*`, `?`, `**`) to an anchored regular expression.
function ConvertTo-RebrandGlobRegex {
    param([string]$Glob)

    $pattern = [regex]::Escape($Glob) -replace '\\\*\\\*/', '(.*/)?' -replace '\\\*\\\*', '.*' -replace '\\\*', '[^/]*' -replace '\\\?', '[^/]'
    return "^$pattern$"
}

# Lists tracked text files the rebrand may touch: everything except anvil-owned
# files, excluded paths and binary files.
function Get-RebrandTargetFiles {
    param([Parameter(Mandatory)][string]$RepoRoot, [string[]]$Exclude = @())

    $owned = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($path in Get-AnvilOwnedPaths -RepoRoot $RepoRoot) { $owned.Add($path) | Out-Null }
    $excludeRegexes = @($Exclude | ForEach-Object { ConvertTo-RebrandGlobRegex $_ })

    $tracked = @(git -C $RepoRoot ls-files)
    if ($LASTEXITCODE -ne 0) { throw "rebrand: 'git ls-files' failed in '$RepoRoot'." }

    foreach ($path in $tracked) {
        if ($owned.Contains($path)) { continue }
        if ($excludeRegexes | Where-Object { $path -match $_ }) { continue }
        $full = Join-Path $RepoRoot $path
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        $bytes = [System.IO.File]::ReadAllBytes($full)
        if ([array]::IndexOf($bytes, [byte]0) -ge 0) { continue }
        $path
    }
}

# Reads a text file, remembering whether it starts with a UTF-8 byte order mark.
function Read-RebrandFile {
    param([string]$FullPath)

    $bytes = [System.IO.File]::ReadAllBytes($FullPath)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset = if ($hasBom) { 3 } else { 0 }
    return [pscustomobject]@{
        Text   = [System.Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset)
        HasBom = $hasBom
    }
}

function Write-RebrandFile {
    param([string]$FullPath, [string]$Text, [bool]$HasBom)

    [System.IO.File]::WriteAllText($FullPath, $Text, [System.Text.UTF8Encoding]::new($HasBom))
}

# Splits text into segments; Managed is $true for an anvil-managed region,
# marker lines included. Concatenating every Text gives back the input.
function Split-RebrandSegments {
    param([string]$Text)

    $segments = [System.Collections.Generic.List[object]]::new()
    $current = [System.Text.StringBuilder]::new()
    $managed = $false
    foreach ($line in [regex]::Split($Text, '(?<=\n)')) {
        if ($line -eq '') { continue }
        if (-not $managed -and $line.Contains($script:AnvilRegionStart)) {
            if ($current.Length -gt 0) { $segments.Add([pscustomobject]@{ Text = $current.ToString(); Managed = $false }) }
            $current.Clear() | Out-Null
            $managed = $true
        }
        $current.Append($line) | Out-Null
        if ($managed -and $line.Contains($script:AnvilRegionEnd)) {
            $segments.Add([pscustomobject]@{ Text = $current.ToString(); Managed = $true })
            $current.Clear() | Out-Null
            $managed = $false
        }
    }
    if ($current.Length -gt 0) { $segments.Add([pscustomobject]@{ Text = $current.ToString(); Managed = $managed }) }
    return $segments.ToArray()
}

# Builds one regex that matches any rule's From, longest first. A newline in
# From also matches CRLF.
function New-RebrandRuleRegex {
    param([object[]]$Rules)

    $alternatives = $Rules | Sort-Object { $_.From.Length } -Descending | ForEach-Object {
        ([regex]::Escape($_.From)) -replace '\\n', '\r?\n'
    }
    return [regex]::new(($alternatives -join '|'))
}

# Applies the rules to unmanaged segments in one pass, so replaced text is never
# matched again. Returns the new text and one change record per matched line.
function Convert-RebrandText {
    param([string]$Text, [object[]]$Rules)

    $changes = [System.Collections.Generic.List[object]]::new()
    if ($Rules.Count -eq 0) { return [pscustomobject]@{ Text = $Text; Changes = @() } }

    $regex = New-RebrandRuleRegex -Rules $Rules
    $byFrom = @{}
    foreach ($rule in $Rules) { $byFrom[$rule.From] = $rule.To }

    $output = [System.Text.StringBuilder]::new()
    foreach ($segment in Split-RebrandSegments -Text $Text) {
        if ($segment.Managed) {
            $output.Append($segment.Text) | Out-Null
            continue
        }
        $base = $output.Length
        $converted = $regex.Replace($segment.Text, {
                param($match)
                $key = $match.Value -replace "`r`n", "`n"
                $prefix = $Text.Substring(0, $base + $match.Index)
                $changes.Add([pscustomobject]@{
                        Line = ([regex]::Matches($prefix, "`n")).Count + 1
                        From = $key
                        To   = $byFrom[$key]
                    })
                $replacement = $byFrom[$key]
                if ($match.Value.Contains("`r`n")) { $replacement = $replacement -replace '(?<!\r)\n', "`r`n" }
                return $replacement
            })
        $output.Append($converted) | Out-Null
    }
    return [pscustomobject]@{ Text = $output.ToString(); Changes = $changes.ToArray() }
}

# Rewrites whole files listed under Files, then applies the rules to every other
# target file. Writes only with -Apply. Returns one record per change.
function Invoke-Rebrand {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][object]$Config,
        [switch]$Apply
    )

    $wholeFiles = @{}
    foreach ($file in $Config.Files) { $wholeFiles[$file.Path] = $file.Content }

    foreach ($path in Get-RebrandTargetFiles -RepoRoot $RepoRoot -Exclude $Config.Exclude) {
        $full = Join-Path $RepoRoot $path
        $file = Read-RebrandFile -FullPath $full

        if ($wholeFiles.ContainsKey($path)) {
            if ($file.Text -ne $wholeFiles[$path]) {
                [pscustomobject]@{ Path = $path; Line = 0; From = '(whole file)'; To = '(Files entry)' }
                if ($Apply) { Write-RebrandFile -FullPath $full -Text $wholeFiles[$path] -HasBom $file.HasBom }
            }
            continue
        }

        $result = Convert-RebrandText -Text $file.Text -Rules $Config.Rules
        if ($result.Changes.Count -eq 0) { continue }
        foreach ($change in $result.Changes) {
            [pscustomobject]@{ Path = $path; Line = $change.Line; From = $change.From; To = $change.To }
        }
        if ($Apply) { Write-RebrandFile -FullPath $full -Text $result.Text -HasBom $file.HasBom }
    }
}

# Lists lines that still match a Residue pattern and no Allow pattern, outside
# anvil-owned files, anvil regions and excluded paths.
function Find-RebrandResidue {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][object]$Config
    )

    if ($Config.Residue.Patterns.Count -eq 0) { return }
    $patterns = [regex]::new(($Config.Residue.Patterns | ForEach-Object { "(?:$_)" }) -join '|')
    $allow = if ($Config.Residue.Allow.Count -gt 0) {
        [regex]::new(($Config.Residue.Allow | ForEach-Object { "(?:$_)" }) -join '|')
    }

    foreach ($path in Get-RebrandTargetFiles -RepoRoot $RepoRoot -Exclude $Config.Exclude) {
        $text = (Read-RebrandFile -FullPath (Join-Path $RepoRoot $path)).Text
        $lineNumber = 1
        foreach ($segment in Split-RebrandSegments -Text $text) {
            foreach ($line in [regex]::Split($segment.Text, '(?<=\n)')) {
                if ($line -eq '') { continue }
                if (-not $segment.Managed -and $patterns.IsMatch($line) -and -not ($allow -and $allow.IsMatch($line))) {
                    [pscustomobject]@{ Path = $path; Line = $lineNumber; Text = $line.TrimEnd() }
                }
                $lineNumber++
            }
        }
    }
}
