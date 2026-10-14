# Patching third-party crates with a fork

When a dependency needs a fix that upstream has not released yet, and waiting
is not an option, fork the dependency, commit the fix there, and point this
workspace at the fork with `[patch.crates-io]`. Send the same fix upstream, and
delete the patch once upstream publishes a release that contains it.

This is how projects such as [Zed](https://github.com/zed-industries/zed) and
[Agave](https://github.com/anza-xyz/agave) carry urgent fixes.

## What a patch does and does not reach

`[patch.crates-io]` replaces a crate everywhere in this workspace's dependency
graph, transitive dependencies included: if `foo` depends on `bar` and `bar`
has the bug, patch `bar` alone; there is no need to fork `foo`.

It applies only to builds of this workspace. Users of a crate published from
this repository get the crates.io release of the dependency, not the fork, and
crates.io rejects packages with git dependencies. A published crate must
therefore work without the fix. If it cannot, publish the fork under a new
name and depend on it with `package = "..."` instead; that case is outside
this guide.

## Adding a patch

1. **Fork** the upstream repository to an organization or personal account.
   An organization account survives people leaving; if the fork lives in a
   personal account, the tracking issue (step 5) names its owner.

2. **Branch from the released version** that `Cargo.lock` currently resolves
   (for example the upstream tag `v1.4.2`), not from upstream's default branch,
   and commit only the fix. Keep the version in the fork's `Cargo.toml`
   unchanged: Cargo uses the patch only if that version satisfies every
   requirement on the crate in the workspace, and otherwise ignores it with a
   warning that the patch was not used in the crate graph.

3. **Patch** the root `Cargo.toml`, pinned to a commit with `rev`, never to a
   branch, so every build resolves the same code:

   ```toml
   [patch.crates-io]
   # Fixes <one-line description of the bug>.
   # Upstream: https://github.com/upstream-org/foo/pull/123
   # Tracking: https://github.com/<owner>/<repo>/issues/45
   # Remove once a foo release contains the fix.
   foo = { git = "https://github.com/example-org/foo", rev = "0123456789abcdef0123456789abcdef01234567" }
   ```

   When several crates come from the same repository (for example `foo` and
   `foo-sys`), patch each one with the same `git` and `rev`.

4. **Allow the source** in `deny.toml`. The generated `[sources]` section denies
   unknown git sources, so `just anvil-deny` fails until the fork is listed in
   `allow-git` (a trailing `.git` in either URL does not matter):

   ```toml
   allow-git = [
       "https://github.com/example-org/foo",
   ]
   ```

5. **Track** the removal: open an issue that links the upstream pull request,
   and send the fix upstream if it is not there yet.

6. **Update the lock file** with `cargo update -p foo`, then confirm the fork is
   in use: `cargo tree -i foo` lists the dependency with its
   `git+https://...` source.

Dependabot does not propose updates for git sources, so a patched dependency
stays on the pinned commit until someone moves it.

## Updating or removing a patch

- To pick up more fixes, commit them on the same fork branch, then move `rev`
  to the new commit and run `cargo update -p foo`.
- Once upstream publishes a release with the fix, delete the `[patch.crates-io]`
  entry and its `allow-git` entry, raise the version requirement on the crate
  to that release where it is a direct dependency, run `cargo update -p foo`,
  and close the tracking issue.
