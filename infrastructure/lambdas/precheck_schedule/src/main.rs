use lambda_runtime::{run, service_fn, Error, LambdaEvent};
use zeitplan_libs::{schedule::Schedule, schedule::ValidationError};

use serde::{Deserialize, Serialize};

/// This is a made-up example. Requests come into the runtime as unicode
/// strings in json format, which can map to any structure that implements `serde::Deserialize`
/// The runtime pays no attention to the contents of the request payload.
#[derive(Deserialize)]
struct Request {
    schedule: Schedule<u16>,
}

/// This is a made-up example of what a response structure may look like.
/// There is no restriction on what it can be. The runtime requires responses
/// to be serialized into json. The runtime pays no attention
/// to the contents of the response payload.
#[derive(Serialize)]
struct Response {
    success: bool,
    error: Option<String>,
}

/// This is the main body for the function.
/// Write your code inside it.
/// There are some code example in the following URLs:
/// - https://github.com/awslabs/aws-lambda-rust-runtime/tree/main/examples
/// - https://github.com/aws-samples/serverless-rust-demo/
async fn function_handler(event: LambdaEvent<Request>) -> Result<Response, String> {
    // Extract some useful info from the request
    Ok(match event.payload.schedule.setup() {
        Ok(_) => Response {
            success: true,
            error: None,
        },
        Err(err) => Response {
            success: false,
            error: match err {
                ValidationError::PigeonholeError {
                    pigeons,
                    pigeon_holes,
                } => Some(format!(
                    "Trying to schedule {} slots of meetings and only {} slots to schedule in!",
                    pigeons, pigeon_holes
                )),
                ValidationError::InvalidData { error: _ } => Some(String::from("Invalid data!")),
                _ => None,
            },
        },
    })
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        // disable printing the name of the module in every log line.
        .with_target(false)
        // disabling time is handy because CloudWatch will add the ingestion time.
        .without_time()
        .init();

    run(service_fn(function_handler)).await
}
