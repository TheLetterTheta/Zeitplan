#![no_main]
use libfuzzer_sys::fuzz_target;
use zeitplan_libs::time::TimeRange;

fuzz_target!(|data: TimeRange<u8>| {
    // fuzzed code goes here
});
