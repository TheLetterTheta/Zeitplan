#![no_main]
use libfuzzer_sys::fuzz_target;
use std::collections::HashSet;
use zeitplan_libs::time::{Blocks, TimeMerge, TimeRange, Windowed};

fuzz_target!(|data: (Vec<TimeRange<u8>>, u8 , Vec<TimeRange<u8 >>)| {
    let available = data.0;
    let duration = data.1;
    let blocks = data.2;

    let mut windows = available.iter().windowed(duration);

    assert!(
        windows.all(|w| w.end() - w.start() == duration - 1),
        "Duration should be the same for all windows"
    );

    let availability = available.iter().blocks(blocks.iter()).collect::<Vec<_>>();
    let available = &available
        .iter()
        .time_merge()
        .collect::<Vec<_>>()
        .iter()
        .windowed(1)
        .collect::<HashSet<TimeRange<_>>>();

    assert!(
        &availability
            .iter()
            .windowed(1)
            .all(|w| available.contains(&w)),
        "Each element in available should be in original time"
    );

    let blocks = blocks.iter().windowed(1).collect::<HashSet<TimeRange<_>>>();
    assert!(
        availability
            .iter()
            .windowed(1)
            .all(|w| !blocks.contains(&w)),
        "No element in available should be in blocks"
    );

    let available = windows.collect::<Vec<_>>().iter().time_merge();

    assert!(
        available.clone().zip(available.skip(1)).all(|(l, r)| l < r),
        "Each element is *not* less than the following element"
    );
});
