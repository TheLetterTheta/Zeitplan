#![no_main]
use libfuzzer_sys::fuzz_target;
use zeitplan_libs::schedule::Schedule;

fuzz_target!(|data: Schedule<u8>| {
    // fuzzed code goes here
    // searching for long-running configurations
    data.schedule_meetings(None);
});
