<div align="center">
 <img src="./logo.svg" alt="Oxidizer Logo" width="96">

# The Oxidizer Project

[![CI](https://github.com/microsoft/oxidizer/actions/workflows/anvil-pr.yml/badge.svg)](https://github.com/microsoft/oxidizer/actions/workflows/anvil-pr.yml)
[![Coverage](https://codecov.io/gh/microsoft/oxidizer/graph/badge.svg?token=FCUG0EL5TI)](https://codecov.io/gh/microsoft/oxidizer)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

</div>

This repository contains a set of crates that help you build robust highly scalable services in Rust.

- [The Oxidizer Project](#the-oxidizer-project)
  - [Crates](#crates)
  - [About this Repo](#about-this-repo)
    - [Adding New Crates](#adding-new-crates)
    - [Publishing Crates](#publishing-crates)
    - [Documenting Crates](#documenting-crates)
    - [CI Workflows](#ci-workflows)
    - [Pull Request Gates](#pull-request-gates)
    - [Local Verification](#local-verification)
  - [Trademarks](#trademarks)

## Crates

These are the primary crates built out of this repo:

<!--
  One line per crate, sorted by name, in this form:

    - [`my_crate`](./crates/my_crate/README.md) - One-sentence description.

  scripts/add-crate.ps1 adds the line for a new crate (macro crates are left
  out), so keep at least one entry and keep the list contiguous. Links to a
  crate's README sections can go under its entry, indented by two spaces;
  add-crate.ps1 then sorts only the entries above the first indented line:

    - [`my_crate`](./crates/my_crate/README.md) - One-sentence description.
      - [Migration from v1](./crates/my_crate/README.md#migration-from-v1)
-->

- [`example_seed`](./crates/example_seed/README.md) - Seed crate that keeps the template workspace buildable

## About this Repo

The following sections explain the overall engineering process we use
in this repo.

To set up a local PC environment capable of exercising all the tooling used by this repo's development processes,
you can follow the guide in [DEVELOPMENT.md](./DEVELOPMENT.md).

### Adding New Crates

Adding a new crate to this repo is done by running the `scripts\add-crate.ps1` script.
It will prompt you for a few bits of state, and then will get everything wired up that
needs to be.

The `add-crate` script does the following:

- Adds an entry for the crate to the [Crates](#crates) section in this README file.

- Adds an entry for the crate to the top-level [CHANGELOG.md](./CHANGELOG.md) file.

- Prepares a `README.md` file for the crate, setup for use with [
  `cargo-doc2readme`](https://crates.io/crates/cargo-doc2readme)
  with a set of appropriate CI badges.

- Creates an empty `CHANGELOG.md` file for the crate, which will later get populated by the `scripts\release-packages.ps1`
  script.

- Creates placeholder `logo.png` and `favicon.ico` files for the crate, which you're expected to replace with legit
  crab-themed
  logo and icon.

### Publishing Crates

Releasing new versions of crates to [crates.io](https://crates.io) is handled by
an internal Microsoft automation process. To release a new version of any crate, follow
this simple process:

1. Make sure the changes you want to release have all been committed to the repo.

2. Create a branch off of main.

3. Run `./scripts/release-packages.ps1 -Packages '<crate_name>@<change_type>'` to update versions and changelogs.
   The change type for each package is one of `breaking`, `nonbreaking`, `patch`, or an explicit version like
   `1.0.0`. To release several crates together, list them all in the same `-Packages` argument
   (for example, `'foo@nonbreaking','bar@patch'`); the script plans the entire release up-front.

4. Create a PR like normal to push changes out.

Once your PR is merged, automation will kick in. It will tag the
commit and push the crate to crates.io.

### Documenting Crates

We want our crates to have world-class documentation such that our customers can enjoy discovering and using our
features. We expect our Rust code to be fully documented in the normal Rust way, and we introduce two doc-related
automation processes:

- The `README.md` file in each crate's directory is auto-generated from the crate-level documentation.
  We use the [`cargo-doc2readme`](https://crates.io/crates/cargo-doc2readme) tool which reads the crate docs, resolves intra-doc links, and
  generates the `README.md` file using a shared template. A pull request gate ensures the `README.md` file
  always reflects the latest crate documentation.

- The `CHANGELOG.md` file in each crate's directory is auto-generated from the commits to a crate's directory by the
  `scripts/release-packages.ps1` script.

To generate documentation locally with all features enabled (including feature-gated items), run:

```shell
just anvil-doc-build --open
```

Anvil uses the repository's selected stable toolchain for this command. The
script generates documentation and opens it in your default browser.

### CI Workflows

Cargo Anvil owns Rust verification:

- `anvil-pr.yml` runs impact-scoped pull request and merge-group checks across
  the supported operating-system and architecture matrix.
- `anvil-scheduled.yml` runs full-workspace backstops and longer checks.

Both workflows invoke the same generated `just anvil-*` recipes developers use
locally. Codecov reports remain available for detailed inspection, while the
Anvil coverage gate is authoritative.

### Pull Request Gates

The Anvil pull request tier covers formatting, linting, manifest policy,
documentation, dependency policy, SemVer analysis, external-type exposure,
tests, coverage, examples, MSRV compatibility, Miri, cargo-careful, Loom,
Bolero, and mutation testing. Run the complete tier locally with:

```shell
just anvil-pr
```

### Local Verification

Run `just anvil-setup` once to install the toolchains and tools selected by the
Anvil catalog. Useful focused commands include:

```shell
just anvil-build
just anvil-clippy
just anvil-fmt --fix
just anvil-readme --fix
just anvil-spellcheck
just anvil-pr-fast
```

Tool versions are generated in `justfiles/anvil/versions.just` and updated with
Cargo Anvil. Do not maintain a second tool-version list.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft
sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
