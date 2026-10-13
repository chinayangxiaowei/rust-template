// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

//! Integration tests: exercise `example_seed` only through its public API, as a
//! dependent crate would.

use example_seed::checked_sum;

#[test]
fn sums_values_from_a_vec() {
    let values: Vec<u64> = (1..=10).collect();

    assert_eq!(checked_sum(&values), Some(55));
}

#[test]
fn reports_overflow_from_a_subslice() {
    let values = [7, u64::MAX, 1];

    assert_eq!(checked_sum(&values[1..]), None);
}
