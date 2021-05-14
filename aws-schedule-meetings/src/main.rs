use lambda_runtime::{error::LambdaErrorExt, lambda, Context};
use std::error::Error;
use std::collections::HashMap;
use std::fmt;
use std::env;
use zeitplan_libs::{ScheduleInput, schedule_meetings, TimeRange, ValidationError};

fn main() -> Result<(), Box<dyn Error>> {
    lambda!(schedule_meetings_short);

    Ok(())
}

fn schedule_meetings_short(input: ScheduleInput, _: Context) -> Result<HashMap<String, TimeRange>, AwsError> {
    let execution_limit: Option<usize> = env::var("EXECUTION_LIMIT").map(|n| n.parse().unwrap_or(1)).ok();
    input.validate()?;
    let result = schedule_meetings(&input, execution_limit)?
        .iter()
        .map(|(k, v)| (k.to_string(), *v) )
        .collect();
    Ok(result)
}

#[derive(Debug)]
struct AwsError(ValidationError);
impl LambdaErrorExt for AwsError {
    fn error_type(&self) -> &str {
        match self.0 {
            ValidationError::UnsupportedLength {
                expected: _,
                found: _,
            } => "UnsupportedLength",
            ValidationError::OverlappingTimeRange {
                location: _,
                value: _,
            } => "OverlappingTimeRange",
            ValidationError::NoSolution => "NoSolution"
        }
    }
}

impl Error for AwsError {}

impl fmt::Display for AwsError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(f)
    }
}

impl From<ValidationError> for AwsError {
    fn from(validation_error: ValidationError) -> AwsError {
        AwsError(validation_error)
    }
}
