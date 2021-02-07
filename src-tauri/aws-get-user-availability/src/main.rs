use lambda_runtime::{error::HandlerError, lambda, Context};
use std::error::Error;
use zeitplan_libs::Input;

fn main() -> Result<(), Box<dyn Error>> {
    lambda!(sort);

    Ok(())
}

fn sort(mut input: Input, _: Context) -> Result<Input, HandlerError> {
    input.get_user_availability();
    Ok(input)
}
