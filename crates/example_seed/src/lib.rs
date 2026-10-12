// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

#![cfg_attr(coverage_nightly, feature(coverage_attribute))]
#![cfg_attr(docsrs, feature(doc_cfg))]

//! This is my crate. It is a very good crate, it is a very nice crate.

#![doc(html_logo_url = "https://media.githubusercontent.com/media/microsoft/oxidizer/refs/heads/main/crates/CRATE_NAME/logo.png")]
#![doc(html_favicon_url = "https://media.githubusercontent.com/media/microsoft/oxidizer/refs/heads/main/crates/CRATE_NAME/favicon.ico")]

/// Adds `values`, returning `None` if the total does not fit in a `u64`.
///
/// # Examples
///
/// ```
/// assert_eq!(example_seed::checked_sum(&[1, 2, 3]), Some(6));
/// assert_eq!(example_seed::checked_sum(&[u64::MAX, 1]), None);
/// ```
#[must_use]
pub fn checked_sum(values: &[u64]) -> Option<u64> {
    values.iter().try_fold(0_u64, |total, &value| total.checked_add(value))
}

#[cfg(test)]
#[cfg_attr(coverage_nightly, coverage(off))]
mod tests {
    use super::*;

    #[test]
    fn empty_slice_sums_to_zero() {
        assert_eq!(checked_sum(&[]), Some(0));
    }

    #[test]
    fn values_are_added() {
        assert_eq!(checked_sum(&[2, 3, 5]), Some(10));
    }

    #[test]
    fn overflow_is_reported_as_none() {
        assert_eq!(checked_sum(&[u64::MAX, 1]), None);
    }
}
