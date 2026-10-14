# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

BeforeAll {
    . (Join-Path $PSScriptRoot '..\..\..\..\lib\rebrand.ps1')
    $script:TestRepos = [System.Collections.Generic.List[string]]::new()

    # Creates a throwaway git repository with the given files staged, so that
    # `git ls-files` sees them. Returns the repository path.
    function New-RebrandTestRepo {
        param([hashtable]$Files)

        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("rebrand-test-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root | Out-Null
        $script:TestRepos.Add($root)
        foreach ($path in $Files.Keys) {
            $full = Join-Path $root $path
            New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force | Out-Null
            [System.IO.File]::WriteAllText($full, $Files[$path])
        }
        git -C $root init --quiet
        git -C $root add -A
        return $root
    }

    function Read-TestFile {
        param([string]$Root, [string]$Path)
        return [System.IO.File]::ReadAllText((Join-Path $root $Path))
    }

    function New-TestConfig {
        param(
            [object[]]$Rules = @(),
            [string[]]$Exclude = @(),
            [object[]]$Files = @(),
            [hashtable]$Values = @{ org = 'New Corp'; repo = 'new-repo' },
            [hashtable]$Residue = @{ Patterns = @(); Allow = @() }
        )
        return @{ Values = $Values; Rules = $Rules; Files = $Files; Exclude = $Exclude; Residue = $Residue }
    }
}

AfterAll {
    $script:TestRepos | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-RebrandConfig' {
    It 'expands ${name} placeholders in rule and file targets' {
        $config = Resolve-RebrandConfig (New-TestConfig -Rules @(@{ From = 'Old Corp'; To = 'Copyright ${org}' }) `
                -Files @(@{ Path = 'A.md'; Content = 'Contact ${repo}' }))

        $config.Rules[0].To | Should -Be 'Copyright New Corp'
        $config.Files[0].Content | Should -Be 'Contact new-repo'
    }

    It 'rejects a placeholder that has no value' {
        { Resolve-RebrandConfig (New-TestConfig -Rules @(@{ From = 'x'; To = '${missing}' })) } |
            Should -Throw '*missing*'
    }

    It 'rejects an unknown top-level key' {
        $raw = New-TestConfig
        $raw.Rule = @()
        { Resolve-RebrandConfig $raw } | Should -Throw '*Rule*'
    }

    It 'rejects a rule with an empty From' {
        { Resolve-RebrandConfig (New-TestConfig -Rules @(@{ From = ''; To = 'x' })) } | Should -Throw '*From*'
    }
}

Describe 'Invoke-Rebrand' {
    It 'replaces every rule and reports the changed lines' {
        $root = New-RebrandTestRepo @{ 'README.md' = "# Old Corp`nby old-repo`n" }
        $config = Resolve-RebrandConfig (New-TestConfig -Rules @(
                @{ From = 'Old Corp'; To = '${org}' },
                @{ From = 'old-repo'; To = '${repo}' }))

        $changes = Invoke-Rebrand -RepoRoot $root -Config $config -Apply

        Read-TestFile $root 'README.md' | Should -Be "# New Corp`nby new-repo`n"
        $changes.Path | Should -Be @('README.md', 'README.md')
        $changes.Line | Should -Be @(1, 2)
    }

    It 'does not write files without -Apply' {
        $root = New-RebrandTestRepo @{ 'README.md' = "Old Corp`n" }
        $config = Resolve-RebrandConfig (New-TestConfig -Rules @(@{ From = 'Old Corp'; To = '${org}' }))

        $changes = Invoke-Rebrand -RepoRoot $root -Config $config

        @($changes).Count | Should -Be 1
        Read-TestFile $root 'README.md' | Should -Be "Old Corp`n"
    }

    It 'reports nothing when run a second time' {
        $root = New-RebrandTestRepo @{ 'README.md' = "Old Corp`n" }
        $config = Resolve-RebrandConfig (New-TestConfig -Rules @(@{ From = 'Old Corp'; To = '${org}' }))

        Invoke-Rebrand -RepoRoot $root -Config $config -Apply | Out-Null
        $second = Invoke-Rebrand -RepoRoot $root -Config $config -Apply

        @($second).Count | Should -Be 0
    }

    It 'prefers the longest match and never rewrites replaced text' {
        $root = New-RebrandTestRepo @{ 'a.txt' = "Old Corp and Old`n" }
        $config = Resolve-RebrandConfig (New-TestConfig -Rules @(
                @{ From = 'Old'; To = 'Short' },
                @{ From = 'Old Corp'; To = 'Old Corp Renamed' }))

        Invoke-Rebrand -RepoRoot $root -Config $config -Apply | Out-Null

        Read-TestFile $root 'a.txt' | Should -Be "Old Corp Renamed and Short`n"
    }

    It 'matches a multi-line rule in both LF and CRLF files' {
        $root = New-RebrandTestRepo @{ 'lf.md' = "a`nline one`nline two`nb`n"; 'crlf.md' = "a`r`nline one`r`nline two`r`nb`r`n" }
        $config = Resolve-RebrandConfig (New-TestConfig -Rules @(@{ From = "line one`nline two`n"; To = '' }))

        Invoke-Rebrand -RepoRoot $root -Config $config -Apply | Out-Null

        Read-TestFile $root 'lf.md' | Should -Be "a`nb`n"
        Read-TestFile $root 'crlf.md' | Should -Be "a`r`nb`r`n"
    }

    It 'skips files owned by cargo anvil' {
        $root = New-RebrandTestRepo @{
            '.anvil.lock'      = "version = 1`n`n[[file]]`npath = `"owned.yml`"`nchecksum = `"sha256:0`"`n"
            'owned.yml'        = "Old Corp`n"
            'mine.yml'         = "Old Corp`n"
        }
        $config = Resolve-RebrandConfig (New-TestConfig -Rules @(@{ From = 'Old Corp'; To = '${org}' }) -Exclude @('.anvil.lock'))

        Invoke-Rebrand -RepoRoot $root -Config $config -Apply | Out-Null

        Read-TestFile $root 'owned.yml' | Should -Be "Old Corp`n"
        Read-TestFile $root 'mine.yml' | Should -Be "New Corp`n"
    }

    It 'leaves anvil-managed regions untouched and rewrites the text around them' {
        $text = "Old Corp`n# >>> anvil-managed: r1`nOld Corp`n# <<< anvil-managed: r1`nOld Corp`n"
        $root = New-RebrandTestRepo @{ 'deny.toml' = $text }
        $config = Resolve-RebrandConfig (New-TestConfig -Rules @(@{ From = 'Old Corp'; To = '${org}' }))

        Invoke-Rebrand -RepoRoot $root -Config $config -Apply | Out-Null

        Read-TestFile $root 'deny.toml' |
            Should -Be "New Corp`n# >>> anvil-managed: r1`nOld Corp`n# <<< anvil-managed: r1`nNew Corp`n"
    }

    It 'skips excluded paths, including ** globs' {
        $root = New-RebrandTestRepo @{
            '.ado/pipelines/p.yml' = "Old Corp`n"
            'docs/deep/x.md'       = "Old Corp`n"
            'docs/y.md'            = "Old Corp`n"
        }
        $config = Resolve-RebrandConfig (New-TestConfig -Rules @(@{ From = 'Old Corp'; To = '${org}' }) `
                -Exclude @('.ado/**', 'docs/deep/*.md'))

        Invoke-Rebrand -RepoRoot $root -Config $config -Apply | Out-Null

        Read-TestFile $root '.ado/pipelines/p.yml' | Should -Be "Old Corp`n"
        Read-TestFile $root 'docs/deep/x.md' | Should -Be "Old Corp`n"
        Read-TestFile $root 'docs/y.md' | Should -Be "New Corp`n"
    }

    It 'skips binary files' {
        $root = New-RebrandTestRepo @{ 'a.txt' = "Old Corp`n" }
        [System.IO.File]::WriteAllBytes((Join-Path $root 'logo.png'), [byte[]](0x4F, 0x6C, 0x64, 0x00, 0x43))
        git -C $root add -A
        $config = Resolve-RebrandConfig (New-TestConfig -Rules @(@{ From = 'Old'; To = 'New' }))

        $changes = Invoke-Rebrand -RepoRoot $root -Config $config -Apply

        $changes.Path | Should -Not -Contain 'logo.png'
    }

    It 'keeps a UTF-8 byte order mark' {
        $root = New-RebrandTestRepo @{ 'a.txt' = 'placeholder' }
        [System.IO.File]::WriteAllText((Join-Path $root 'a.txt'), "Old Corp`n", [System.Text.UTF8Encoding]::new($true))
        $config = Resolve-RebrandConfig (New-TestConfig -Rules @(@{ From = 'Old Corp'; To = '${org}' }))

        Invoke-Rebrand -RepoRoot $root -Config $config -Apply | Out-Null

        $bytes = [System.IO.File]::ReadAllBytes((Join-Path $root 'a.txt'))
        $bytes[0..2] | Should -Be @(0xEF, 0xBB, 0xBF)
        Read-TestFile $root 'a.txt' | Should -Be "New Corp`n"
    }

    It 'replaces whole files listed under Files' {
        $root = New-RebrandTestRepo @{ 'SECURITY.md' = "Old Corp policy`n" }
        $config = Resolve-RebrandConfig (New-TestConfig -Files @(@{ Path = 'SECURITY.md'; Content = 'Report to ${org}.' + "`n" }))

        $changes = Invoke-Rebrand -RepoRoot $root -Config $config -Apply

        Read-TestFile $root 'SECURITY.md' | Should -Be "Report to New Corp.`n"
        $changes.Path | Should -Be @('SECURITY.md')
    }
}

Describe 'Find-RebrandResidue' {
    It 'reports matching lines that are not allowed' {
        $root = New-RebrandTestRepo @{ 'a.md' = "fine`nOld Corp left`nOld Corp Guidelines are external`n" }
        $config = Resolve-RebrandConfig (New-TestConfig -Residue @{ Patterns = @('Old Corp'); Allow = @('Old Corp Guidelines') })

        $residue = Find-RebrandResidue -RepoRoot $root -Config $config

        @($residue).Count | Should -Be 1
        $residue[0].Path | Should -Be 'a.md'
        $residue[0].Line | Should -Be 2
    }

    It 'ignores anvil-owned files, anvil regions and excluded paths' {
        $root = New-RebrandTestRepo @{
            '.anvil.lock' = "[[file]]`npath = `"owned.yml`"`n"
            'owned.yml'   = "Old Corp`n"
            'deny.toml'   = "# >>> anvil-managed: r`nOld Corp`n# <<< anvil-managed: r`n"
            '.ado/p.yml'  = "Old Corp`n"
        }
        $config = Resolve-RebrandConfig (New-TestConfig -Exclude @('.ado/**', '.anvil.lock') `
                -Residue @{ Patterns = @('Old Corp'); Allow = @() })

        @(Find-RebrandResidue -RepoRoot $root -Config $config).Count | Should -Be 0
    }
}

Describe 'Repository rebrand configuration' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..')).Path
    }

    It 'loads and resolves every placeholder' {
        $config = Resolve-RebrandConfig (Import-PowerShellDataFile (Join-Path $script:RepoRoot 'rebrand.psd1'))
        @($config.Rules).Count | Should -BeGreaterThan 0
    }

    It 'allows git dependencies from the owner account in deny.toml' {
        $config = Resolve-RebrandConfig (Import-PowerShellDataFile (Join-Path $script:RepoRoot 'rebrand.psd1'))
        $deny = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'deny.toml'))
        $owner = (Import-PowerShellDataFile (Join-Path $script:RepoRoot 'rebrand.psd1')).Values.owner

        $result = Convert-RebrandText -Text $deny -Rules $config.Rules

        $result.Text | Should -Match ('(?m)^\[sources\.allow-org\]\r?\ngithub = \["' + [regex]::Escape($owner) + '"\]$')
    }

    It 'excludes every anvil-owned file that cargo-heather checks' {
        # After a rebrand the repository's license header changes, but files that
        # cargo anvil owns keep the upstream header. cargo-heather must skip them.
        $heather = Get-Content (Join-Path $script:RepoRoot '.cargo-heather.toml') -Raw
        $list = [regex]::Match($heather, '(?m)^exclude\s*=\s*\[([^\]]*)\]').Groups[1].Value
        $excluded = [regex]::Matches($list, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
        $checked = Get-AnvilOwnedPaths -RepoRoot $script:RepoRoot |
            Where-Object { $_ -match '\.(rs|toml|ps1|psd1|psm1|just)$|(^|/)(justfile|constants\.env)$' }

        foreach ($path in $checked) {
            $covered = $excluded | Where-Object { $path -eq $_ -or $path.StartsWith("$_/") }
            $covered | Should -Not -BeNullOrEmpty -Because "$path keeps the upstream header after a rebrand"
        }
    }
}
