# Benchmarks

This chapter covers the conventions for writing Criterion (wall-clock)
benchmarks. See [`docs/naming.md`](naming.md) for file and identifier naming.

## Benchmark design

Unless otherwise prompted, create single-threaded synchronous Criterion
benchmarks. Use benchmark groups to group related benchmarks that make sense to
compare to each other.

Focus on benchmarking elementary operations, do not create benchmarks with lots of
long-winded logic. We generally want to benchmark a single API call or at most a
sequence of closely coupled API calls.

Only the functionality being benchmarked should be inside the `.iter()` closure,
with the data setup being either done outside (if not per-iteration) or using the
first "payload preparation" callback of `iter_batched()` (if per-iteration).

Allocation-tracked Criterion benchmarks use `Bencher::iter_custom()` so one
`alloc_tracker` measurement covers every iteration in the sample. Use the
`benchmarking` crate to keep timing behavior consistent:

- `time_sample()` runs a synchronous operation without prepared input.
- `time_sample_async()` runs sequential asynchronous operations; await it within
  one caller-managed runtime entry.
- `time_sample_with_inputs()` accepts one caller-prepared input per iteration.
  It starts measurement after setup, retains inputs and outputs through the timed
  region, and ends measurement before teardown.

Prepare the complete input vector before calling `time_sample_with_inputs()`.
The helper deliberately does not choose a Criterion batching policy or split a
sample into chunks. Use raw `iter_custom()` timing only when the shared helpers
cannot express the benchmark, and document the special timing requirement in the
benchmark.

If multithreaded benchmarks are truly appropriate, use `bench_on_threadpool()` for
them. When using this for multithreaded benchmarks, also run any single-threaded
benchmarks via `bench_on_threadpool()` to ensure that overheads are comparable.

Inside the benchmark closure, use `std::hint::black_box()` to consume output
values from the code being benchmarked, to avoid unrealistic eager optimizations
due to output values that are discarded.

Benchmarks that are meant to be compared to each other must be in the same
benchmark function and in the same benchmark group.

Do not forget to register benchmarks in `Cargo.toml`.

Benchmark file names and Criterion group names follow strict conventions
documented in [`docs/naming.md`](naming.md): the file basename prefixes
Criterion group names.

## Stack pin vs. `Box::pin` on the measured path

Do not use `Box::pin(value)` on the measured path. It allocates a `Box` on the
heap on every iteration, which can easily add 100-200 instructions (or 40-50% of
the measurement) of pure allocator overhead that has nothing to do with the
operation under test. Use `std::pin::pin!(value)` instead — it pins on the stack
with zero allocation. Add a brief inline comment justifying the deviation from the
usual `Box::pin` preference (e.g. "stack-pin to avoid allocator noise on the
measured path"). This is an exception to the workspace-wide rule against the
`pin!` macro (see the examples chapter).

`Box::pin` remains correct in benchmark code that is **not** inside the measured
region:

* Criterion `iter_custom` setup (anything before `Instant::now()`).
* The first ("payload preparation") callback of `iter_batched()`.
* Helper functions that must return `Pin<Box<T>>` across a function boundary (a
  stack pin would dangle).
* Intentional `Box::pin` baselines where the allocation IS what is being
  measured.

