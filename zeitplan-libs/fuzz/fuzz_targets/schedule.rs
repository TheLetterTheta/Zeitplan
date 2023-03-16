#![no_main]
use libfuzzer_sys::fuzz_target;
use std::collections::HashSet;
use zeitplan_libs::{
    schedule::Schedule,
    time::{TimeMerge, TimeRange, Windowed},
};

fuzz_target!(|data: Schedule<u8>| {
    // fuzzed code goes here
    // searching for long-running configurations
    #[cfg(feature = "log")]
    fern::Dispatch::new()
        .format(|out, message, record| {
            out.finish(format_args!(
                "[{}][{}] {}",
                record.target(),
                record.level(),
                message
            ))
        })
        .level(log::LevelFilter::Debug)
        .chain(std::io::stdout())
        .apply();

    if let Ok(schedule) = data.schedule_meetings(None, None, None) {
        let available: Vec<TimeRange<_>> = data.availability.iter().time_merge().collect();
        let schedule_times = schedule.result.iter().map(|m| m.time).collect::<Vec<_>>();
        if let Some(e) = schedule_times.iter().find(|t| {
            !available
                .iter()
                .any(|a| t.start() >= a.start() && t.end() <= a.end())
        }) {
            panic!(
                "Returned TimeRange outside of Available slots: time {:?} not within {:?}",
                e, available
            );
        }

        let mut unique = HashSet::with_capacity(schedule_times.len());
        for t in schedule_times.iter().windowed(1) {
            assert!(unique.insert(t), "Overlapping Time found: {}", t);
        }
    }
});
