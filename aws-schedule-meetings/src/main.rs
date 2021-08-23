use lambda_runtime::{Error, handler_fn, Context};
use zeitplan_libs::schedule::Schedule;
use std::collections::HashMap;
use zeitplan_libs::time::TimeRange;
use std::env;

fn main() -> Result<(), Error> {
    handler_fn(schedule_meetings);

    Ok(())
}

fn schedule_meetings(input: Schedule<u16>, _: Context) -> Result<HashMap<String, TimeRange<u16>>, Error> {
    let execution_limit: Option<usize> = env::var("EXECUTION_LIMIT").map(|n| n.parse().unwrap_or(1)).ok();
    Ok(
        input
           .schedule_meetings(execution_limit)
           .map( |map| map.into_iter().map(|(k, v)| (v.to_string(), k)).collect())
           ?
    )
}

