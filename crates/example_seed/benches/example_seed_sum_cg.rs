// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

//! Callgrind benchmarks for `checked_sum`.
//!
//! Paired with `example_seed_sum.rs`, which covers the same scenarios under
//! wall-clock measurement. Run with `just bench-cg` on Linux with Valgrind.

#![allow(missing_docs, reason = "no need for API documentation on benchmark code")]
#![cfg_attr(
    target_os = "linux",
    expect(
        clippy::exit,
        clippy::missing_docs_in_private_items,
        unused_qualifications,
        reason = "Triggered by Gungraun macro expansion. Upstream tracking issues are pending."
    )
)]

#[cfg(not(target_os = "linux"))]
fn main() {
    // Gungraun requires Valgrind, which is Linux-only.
}

#[cfg(target_os = "linux")]
mod linux {
    use std::hint::black_box;

    use example_seed::checked_sum;
    use gungraun::{library_benchmark, library_benchmark_group};

    const SMALL: &[u64] = &[1, 2, 3, 4, 5, 6, 7, 8];
    const OVERFLOWING: &[u64] = &[u64::MAX, 1, 2, 3, 4, 5, 6, 7];

    #[library_benchmark]
    fn checked_sum_small() -> Option<u64> {
        checked_sum(black_box(SMALL))
    }

    #[library_benchmark]
    fn checked_sum_overflow() -> Option<u64> {
        checked_sum(black_box(OVERFLOWING))
    }

    library_benchmark_group!(
        name = checked_sum;
        benchmarks = checked_sum_small, checked_sum_overflow
    );
}

#[cfg(target_os = "linux")]
use gungraun::{Callgrind, LibraryBenchmarkConfig};
#[cfg(target_os = "linux")]
pub use linux::checked_sum;

#[cfg(target_os = "linux")]
gungraun::main!(
    config = LibraryBenchmarkConfig::default()
        .tool(Callgrind::with_args(["--branch-sim=yes"]));
    library_benchmark_groups = checked_sum
);
