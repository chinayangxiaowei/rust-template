# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

set windows-shell := ["pwsh.exe", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command"]
set shell := ["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command"]
set script-interpreter := ["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive"]

_default:
    @just --list

# >>> anvil-managed: anvil-imports
import 'justfiles/anvil/mod.just'
# <<< anvil-managed: anvil-imports

# Repository-specific utilities outside Cargo Anvil.

# Apply license boilerplate headers.
license: anvil-license-headers-validate-prereqs
    cargo heather --fix

# Run the Pester suite for the release-related PowerShell scripts.
[arg("scope", long, pattern='(?:unit|integration|scenarios)?')]
[script("pwsh", "-NoProfile")]
test-scripts scope="":
    $ErrorActionPreference = "Stop"
    & ./scripts/tests/Pester/Run-Tests.ps1 -Path "{{ scope }}"

# Replace the template's upstream identity using rebrand.psd1. Mode: preview, apply or check.
[script("pwsh", "-NoProfile")]
rebrand mode="preview":
    $ErrorActionPreference = "Stop"
    switch ("{{ mode }}") {
        "preview" { & ./scripts/rebrand.ps1 }
        "apply" { & ./scripts/rebrand.ps1 -Apply }
        "check" { & ./scripts/rebrand.ps1 -Check }
        default { Write-Error "Unknown mode '{{ mode }}'. Use preview, apply or check." }
    }
    exit $LASTEXITCODE

# Accept every pending `*.anvil-proposed` file by replacing its sibling with Anvil's version.
[script("pwsh", "-NoProfile")]
accept-anvil-proposed:
    $ErrorActionPreference = "Stop"
    $proposals = @(git ls-files --others -- '*.anvil-proposed')
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if ($proposals.Count -eq 0) { Write-Host 'No .anvil-proposed files.'; exit 0 }
    foreach ($proposal in $proposals) {
        $target = $proposal -replace '\.anvil-proposed$', ''
        Move-Item -LiteralPath $proposal -Destination $target -Force
        Write-Host "Accepted $target"
    }

# Run compile-fail tests while iterating on macro diagnostics.
[arg("package", long)]
[arg("filter", long)]
[script("pwsh", "-NoProfile")]
trybuild package filter="": anvil-tool-rustc-validate-prereqs
    $ErrorActionPreference = "Stop"
    cargo {{_anvil_stable_toolchain_args}} test --package "{{ package }}" --all-features --locked --tests -- "{{ filter }}"

# Rewrite compile-fail diagnostic snapshots after an intentional change.
[arg("package", long)]
[arg("filter", long)]
[script("pwsh", "-NoProfile")]
trybuild-overwrite package filter="": anvil-tool-rustc-validate-prereqs
    $ErrorActionPreference = "Stop"
    $env:TRYBUILD = "overwrite"
    cargo {{_anvil_stable_toolchain_args}} test --package "{{ package }}" --all-features --locked --tests -- "{{ filter }}"

# Install the Linux-only Callgrind benchmark runner.
[script("pwsh", "-NoProfile")]
setup-callgrind:
    $ErrorActionPreference = "Stop"
    & ./scripts/install-callgrind-tools.ps1

# Publish a GitHub release for a crate tag.
[arg("repository", long)]
[arg("tag", long)]
publish-gh-release repository tag: anvil-toolchain-nightly-validate-prereqs
    cargo '+{{ rust_nightly }}' -Zscript scripts/publish-gh-release.rs --repo "{{ repository }}" "{{ tag }}"
