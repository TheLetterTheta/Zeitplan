use lambda_runtime::{handler_fn, Context};
use std::collections::BTreeMap;
use std::env;
use zeitplan_libs::schedule::Schedule;
use zeitplan_libs::time::TimeRange;

type Error = Box<dyn std::error::Error + Send + Sync + 'static>;

#[tokio::main]
async fn main() -> Result<(), Error> {
    let func = handler_fn(schedule_meetings);

    lambda_runtime::run(func).await?;
    Ok(())
}

async fn schedule_meetings(
    input: Schedule<u16>,
    _: Context,
) -> Result<BTreeMap<TimeRange<u16>, String>, Error> {
    let execution_limit: Option<usize> = env::var("EXECUTION_LIMIT")
        .map(|n| n.parse().unwrap_or(1))
        .ok();
    Ok(input.schedule_meetings(execution_limit)?)
}
