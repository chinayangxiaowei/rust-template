# Runtime analysis

The runtime-analysis tier complements the ordinary test, coverage, and mutation
tiers. It does not need to repeat every behavioral assertion under every
interpreter. Each check should retain the cases that can expose failures unique
to that check:

- Miri executes code that owns `unsafe` invariants or supplies a distinct input
  path into such code.
- `cargo careful` runs the native suite against a standard library built with
  additional runtime checks.
- Loom exhaustively explores the small concurrency models selected by the
  dedicated `required-features = ["loom"]` targets.
- Bolero exercises operation sequences that hand-written tests do not cover.

## Miri selection

Use `[package.metadata.anvil.miri] exclude = true` when a package contains no
runtime `unsafe` code, does not provide a unique path into an unsafe dependency,
and interpreting its suite would mostly repeat functional coverage. The package
continues to compile when selected packages depend on it, and its complete test
suite continues to run natively and under `cargo careful`.

Package-level exclusions enforce the absence of unsafe code with
`#![forbid(unsafe_code)]`. When a test-only dependency expands to code that
carries an internal `allow(unsafe_code)` attribute (for example a `ctor`-based
initializer), apply the prohibition to non-test builds only with
`#![cfg_attr(not(test), forbid(unsafe_code))]`. The shipped library remains
unable to introduce unsafe code.

Prefer a test-level `#[cfg_attr(miri, ignore = "...")]` when only one
integration scenario lacks Miri-specific value. The reason must name the
coverage retained elsewhere. Use `cfg(miri)` to reduce a stress-test cardinality
instead of ignoring the test when a smaller case reaches the same unsafe or
concurrency path. Native test cardinalities must remain unchanged.

Miri-specific reductions should preserve the transition or boundary that makes
the test valuable rather than preserving an arbitrary native workload size:

- depth and length guards run just beyond their enforced bound;
- oversized-allocation tests use a lower configurable threshold when the
  physical chunk boundary itself is not the subject of the test;
- statistical and differential tests retain representative samples while their
  full populations continue to run natively;
- synchronization tests retain every participating role and at least one
  complete state transition;
- recorder tests use the minimum supported event-ring capacity unless ring
  sizing or wraparound is the behavior under test.

Pure runtime limits, stack-safety stress, formatting breadth, code generation,
and safe integration scenarios may be excluded from Miri when direct tests
continue to exercise the unsafe implementation or dependency path they cover.
The native and `cargo careful` suites remain authoritative for the excluded
stress breadth.

Safe default-constructor, preallocation, formatting, allocation-count, and
hash-table rollback tests do not gain additional value merely by running under
Miri. Prefer a reasoned test-level ignore for those cases while retaining a
smaller test that reaches the package's actual unsafe storage or lifecycle
path. Platform-emulation matrices similarly retain representative Miri cases
for each unsafe callback/lifecycle transition while leaving exhaustive option
and validation combinations to native tests.

The following package-level exclusions are intentional:

- Code-generation and benchmark orchestration packages are covered through
  generated code in consuming crates or by native process-level tests.

Add an entry for each package excluded from Miri, naming the coverage retained
elsewhere. Representative reasons:

<!--
- `my_crate` contains no runtime `unsafe` code. Its behavioral suite runs
  natively and under `cargo careful`; its dependencies retain their own Miri
  coverage.
- `my_crate_cli` is a safe integration layer over `my_crate`. The unsafe
  implementation remains in the Miri-selected `my_crate` package.
- `my_allocator` uses native VM reservations and CPU prefetch instructions that
  have no interpreter backend. Its native suites and `cargo careful` remain
  authoritative.
-->

Do not infer that a safe package is automatically dispensable. Keep it selected
when its runtime tests provide the workspace's only Miri coverage for an unsafe
path in a dependency.

## Target-level selection limitations

The current cargo-anvil catalog supports only package-level Miri exclusion:

```toml
[package.metadata.anvil.miri]
exclude = true
```

It does not expose supported package metadata for excluding individual test
targets. Consequently, `--all-features --tests` may compile and replay empty
Loom or Bolero executables whose source is disabled by `cfg(loom)` or
`cfg(not(miri))`. Do not hand-edit generated `justfiles/anvil/**` to remove
them. Target-level omission requires a cargo-anvil catalog enhancement.

The Bolero recipe likewise has no supported manifest target-exclusion metadata;
on Linux it discovers every `bolero::check!` target and gives each a 60-second
libFuzzer smoke campaign. Repository code must not silently shorten or remove
attacker-facing and unsafe-lifecycle campaigns to work around this limitation.

## Whole-workspace measurement

Use the generated recipe with impact analysis disabled when evaluating the
complete validation boundary:

```powershell
$env:ANVIL_IMPACT = 'off'
just anvil-pr-runtime-analysis
```

Compare warm runs on the same host and toolchain. Report compilation separately
when a clean build is relevant; otherwise, runtime comparisons should not claim
compiler-cache changes as test improvements.
