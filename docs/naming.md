# Naming conventions

This document codifies naming conventions for files and identifiers across the
workspace. See `AGENTS.md` for the broader set of conventions; this file focuses
on naming patterns that need to be consistent across packages.

## Benchmark naming

Criterion (wall-clock) benchmarks live in each package's `benches/`
directory. The naming rules below ensure benchmarks are easy to locate and
produce non-colliding binary names in the shared `target/.../deps/` directory.

### Benchmark file names

Every file in `crates/<crate>/benches/` should be prefixed with either:

* The full name of the package (e.g. `foo/benches/foo_something.rs`), or
* An abbreviated form of the full package name (e.g.
  `foo_bar_baz/benches/fbb_something.rs`).

For packages that follow the `_impl` crate split pattern (see
[`docs/impl-crate-split.md`](impl-crate-split.md)), the `_impl` suffix is
omitted from the benchmark file prefix (e.g. `nm_impl/benches/nm_observe.rs`,
not `nm_impl_observe.rs`).

The crate-name prefix prevents collisions when the resulting bench binaries
land in the shared `target/.../deps/` directory.

Apply this prefix to new benchmark files; some benches predate this
convention and remain unprefixed (e.g. `crates/bytesbuf/benches/view.rs`).

Do not append decorator suffixes like `_bench` or `_benches` — the `benches/`
directory location and `[[bench]]` Cargo table entry already convey that a
file is a benchmark.

### Criterion benchmark groups

Every Criterion `benchmark_group()` call should use a name of the form:

```
<file-basename>/<subgroup>
```

where `<file-basename>` is the benchmark file name without the `.rs`
extension and `<subgroup>` is a short semantic identifier for the group.

Examples for `foo/benches/foo_something.rs`:

```rust
let mut group = c.benchmark_group("foo_something/reads");
// ...
let mut group = c.benchmark_group("foo_something/writes");
```

The `<file-basename>/` prefix means a benchmark's fully qualified Criterion
path (`<group>/<benchmark>`) starts with the file basename, making it
trivial to locate the source file from a benchmark report.

Avoid `::` or other custom separators between segments — Criterion already
uses `/` as the hierarchical separator and that is the only separator that
should appear in group names.

This applies to new benchmark groups; some pre-existing groups use flat
names that predate this convention (e.g. `crates/bytesbuf/benches/view.rs`
uses `"BytesView"` and `"BytesView_slow"`).

