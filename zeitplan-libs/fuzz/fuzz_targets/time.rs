#![no_main]
use libfuzzer_sys::fuzz_target;
use zeitplan_libs::time::{TimeRange, Windowed, TimeMerge};

fuzz_target!(|data: (Vec<TimeRange<u16>>, u16)| {
    let duration = data.1;
    let data = data.0;

    let mut windows = data.iter().windowed(duration);

    assert!(
        windows.all(|w| w.end() - w.start() == duration - 1),
        "Duration should be the same for all windows"
        );

    let data = windows.collect::<Vec<_>>().iter().time_merge();

    assert!(
        data.clone().zip(data.skip(1)).all(|(l, r)| l < r),
        "Each element is *not* less than the following element"
    );
});
