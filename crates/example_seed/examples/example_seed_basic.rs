// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

//! Adds a few numbers with `checked_sum` and shows how overflow is reported.
//!
//! Run with `cargo run --package example_seed --example example_seed_basic`.

use example_seed::checked_sum;

fn main() {
    match checked_sum(&[1, 2, 3]) {
        Some(total) => println!("1 + 2 + 3 = {total}"),
        None => println!("1 + 2 + 3 overflowed"),
    }

    match checked_sum(&[u64::MAX, 1]) {
        Some(total) => println!("u64::MAX + 1 = {total}"),
        None => println!("u64::MAX + 1 overflows u64"),
    }
}
