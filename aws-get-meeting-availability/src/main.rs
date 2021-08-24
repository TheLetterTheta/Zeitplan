use lambda_runtime::{handler_fn, Context, Error};
use serde::Deserialize;
use zeitplan_libs::meeting::Meeting;
use zeitplan_libs::time::{Available, TimeRange};

fn main() -> Result<(), Error> {
    handler_fn(get_meeting_availability);

    Ok(())
}

#[derive(Deserialize)]
struct Input {
    pub meeting: Meeting<u16>,
    pub availability: Vec<TimeRange<u16>>,
}

fn get_meeting_availability(input: Input, _: Context) -> Result<Vec<TimeRange<u16>>, Error> {
    Ok(input.meeting.get_availability(&input.availability))
}
