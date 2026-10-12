# example_seed — Design

## Problem

A new workspace needs at least one crate so that every verification tier has something to build, test, and measure from the first commit.

## Principles

- The crate stays minimal and is replaced or removed once real crates exist.
- Its single function exercises every tier: unit tests, a doctest, the coverage gate, and mutation testing.

## User-visible shape

`checked_sum(&[u64]) -> Option<u64>` adds the values and returns `None` on overflow.

## Out of scope

Any real functionality.
