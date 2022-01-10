#![no_main]
use libfuzzer_sys::fuzz_target;
use zeitplan_libs::time::{TimeRange, TimeMerge};

fuzz_target!(|data: Vec<TimeRange<u8>>| {
    // fuzzed code goes here

    let data = data.iter().time_merge().into_iter().collect::<Vec<_>>();

    assert!(
        data.iter().zip(data.iter().skip(1)).all(|(l, r)| l < r),
        "Each element is *not* less than the following element"
    );
});
