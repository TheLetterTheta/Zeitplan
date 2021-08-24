# Zeitplan Libs
*The core functionality of the Zeitplan scheduling application*

# Benchmarks
This crate uses `Criterion` to perform benchmarks. Use `cargo bench` to run the benchmarks, and
see the performance.

# Tests
This crate should be fully tested. Due to the custom implementation of `Ord` for the `TimeRange` type,
`assert_eq!()` is more not na accurate equality check. See the table below for examples. This crate
internally uses a `TimeRangeTest` type which checks for equality as exact matches of (start, end).

# TimeRange

A Tuple of (start, end) time inclusive.
```rust
struct TimeRange(<N>, <N>);
```

`<N>` is any integer type that can be compared.

`TimeRange` implements a custom `Ord` implementation which denotes two `TimeRange` as equivalent if
any time overlaps (inclusive).

| TimeRange | TimeRange | Ordinal |
|-----------|-----------|---------|
| (0, 0)  a | (1, 1)  b |  a < b  |
| (0, 1)  a | (1, 1)  b |  a = b  |
| (0, 2)  a | (1, 1)  b |  a = b  |
| (0, 2)  a | (2, 2)  b |  a = b  |
| (2, 2)  a | (1, 1)  b |  a > b  |


# Participant

The participant of a meeting.
```rust
struct Participant {
    id: String,
    blocked_times: Vec<TimeRange>
}
```

The `blocked_times` indicates times which a meeting could not be scheduled for this participant.

# Meeting

Something to be scheduled

```rust
struct Meeting {
    id: String,
    participants: Vec<Participant>
}
```
When a meeting is being scheduled, all of the Participant `blocked_times` will be merged together to calculate
when this meeting can be scheduled.
The process for this merge looks something like this:

```rust
meeting
    .participants
    .map(|p| p.blocked_times)
    .flatten()
    .sort()
    .merge()
```
Like so:

| TimeRange | TimeRange | Combined Result |
|-----------|-----------|-----------------|
| (0, 0)  a | (1, 1)  b | (0, 1)          |
| (0, 5)  a | (1, 1)  b | (0, 5)          |
| (0, 0)  a | (2, 2)  b | (0, 0) + (2, 2) |


# Schedule

A collection of meetings to be scheduled. The availability is when the meeting is to be scheduled within.

```rust
struct Schedule {
    meetings: Vec<Meeting>,
    availability: Vec<TimeRange>
}
```

Exports one useful method, `schedule_meetings()` which takes a single parameter `Option<usize>`. This parameter
indicates how long to "search" for a solution. `None` will search forever, while `Some(5)` would stop after 5
invalid solutions. This method returns a `Result<>` with possible errors of `PigeonHoleError { pigeons, pigeon_holes }`
indicating that nothing was attempted, and this configuration was deemed immediately impossible. Otherwise, the
`NoSolution` error will be returned, which indicates that no solution was found.

# Helpers

The `TimeRange` type exports useful Traits that can operate on various `&[TimeRange]` configurations.
```rust
get_availability(&self, available_times) -> Vec<TimeRange>
```
Where `&self` represents blocked times which cannot be scheduled for. This method is used directly by
`Participant` and `Meeting` structs

