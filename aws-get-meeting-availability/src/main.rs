use lambda_runtime::{error::LambdaErrorExt, lambda, Context};
use std::error::Error;
use std::fmt;
use zeitplan_libs::{Input, ValidationError};

fn main() -> Result<(), Box<dyn Error>> {
    lambda!(get_meeting_availability);

    Ok(())
}

fn get_meeting_availability(mut input: Input, _: Context) -> Result<Input, AwsError> {
    input.validate()?;
    input.sort()?;
    input.get_user_availability()?;
    input.get_meeting_availability()?;
    Ok(input)
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
