use lambda_runtime::{handler_fn, Context, Error};
use std::collections::BTreeMap;
use std::env;
use zeitplan_libs::schedule::Schedule;
use zeitplan_libs::time::TimeRange;

fn main() -> Result<(), Error> {
    handler_fn(schedule_meetings);

    Ok(())
}

fn schedule_meetings(
    input: Schedule<u16>,
    _: Context,
) -> Result<BTreeMap<TimeRange<u16>, String>, Error> {
    let execution_limit: Option<usize> = env::var("EXECUTION_LIMIT")
        .map(|n| n.parse().unwrap_or(1))
        .ok();
    Ok(input.schedule_meetings(execution_limit)?)
}
