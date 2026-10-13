# example_seed — Design

## Problem

A new workspace needs at least one crate so that every verification tier has something to build, test, and measure from the first commit.

## Principles

- The crate stays minimal and is replaced or removed once real crates exist.
- Its single function exercises every tier: unit tests, a doctest, the coverage gate, and mutation testing.
- It shows the standard crate layout that new crates follow:

| Path | Purpose | Checked by |
| --- | --- | --- |
| `src/lib.rs` | The library, with unit tests in `mod tests` | tests, coverage, mutation testing |
| `tests/` | Integration tests that use only the public API | tests |
| `examples/` | Runnable examples, named `<crate>_<topic>.rs` | `anvil-examples` |
| `benches/<base>.rs` | Criterion wall-clock benchmarks | `anvil-bench` (build only) |
| `benches/<base>_cg.rs` | Callgrind instruction-count benchmarks, paired with `<base>.rs` | `just bench-cg` (Linux, Valgrind) |
| `docs/design/README.md` | This design document | review |

## User-visible shape

`checked_sum(&[u64]) -> Option<u64>` adds the values and returns `None` on overflow.

## Out of scope

Any real functionality.
