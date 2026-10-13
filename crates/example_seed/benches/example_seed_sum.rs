// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

//! Criterion benchmarks for `checked_sum`.
//!
//! Paired with `example_seed_sum_cg.rs`, which measures the same scenarios as
//! Callgrind instruction counts.

use std::hint::black_box;

use criterion::{Criterion, criterion_group, criterion_main};
use example_seed::checked_sum;

criterion_group!(benches, entrypoint);
criterion_main!(benches);

const SMALL: &[u64] = &[1, 2, 3, 4, 5, 6, 7, 8];
const OVERFLOWING: &[u64] = &[u64::MAX, 1, 2, 3, 4, 5, 6, 7];

fn entrypoint(c: &mut Criterion) {
    let mut group = c.benchmark_group("example_seed_sum/checked_sum");

    group.bench_function("small", |b| {
        b.iter(|| checked_sum(black_box(SMALL)));
    });

    group.bench_function("overflow", |b| {
        b.iter(|| checked_sum(black_box(OVERFLOWING)));
    });

    group.finish();
}
