use lambda_runtime::{run, service_fn, Error, LambdaEvent};
use std::collections::HashSet;
use std::env;
use zeitplan_libs::{
    schedule::ValidationError,
    schedule::{MeetingTime, Schedule},
};

use serde::{Deserialize, Serialize};

/// This is a made-up example. Requests come into the runtime as unicode
/// strings in json format, which can map to any structure that implements `serde::Deserialize`
/// The runtime pays no attention to the contents of the request payload.
#[derive(Deserialize)]
struct Request {
    schedule: Schedule<u16>,
    count: Option<usize>,
}

/// This is a made-up example of what a response structure may look like.
/// There is no restriction on what it can be. The runtime requires responses
/// to be serialized into json. The runtime pays no attention
/// to the contents of the response payload.
#[derive(Serialize)]
struct Response {
    results: Vec<MeetingTime<u16>>,
    failed: HashSet<String>,
    attempts: usize,
}

/// This is the main body for the function.
/// Write your code inside it.
/// There are some code example in the following URLs:
/// - https://github.com/awslabs/aws-lambda-rust-runtime/tree/main/examples
/// - https://github.com/aws-samples/serverless-rust-demo/
async fn function_handler(event: LambdaEvent<Request>) -> Result<Response, ValidationError<u16>> {
    // Extract some useful info from the request
    let meeting_ids: HashSet<String> = event
        .payload
        .schedule
        .meetings
        .iter()
        .map(|meeting| meeting.id.clone())
        .collect();

    let schedule = event.payload.schedule;

    let per_thread = env::var("PER_THREAD")
        .map(|e| e.parse::<usize>().ok())
        .ok()
        .flatten();
    let num_shuffles = env::var("NUM_SHUFFLES")
        .map(|e| e.parse::<usize>().ok())
        .ok()
        .flatten();

    schedule
        .schedule_meetings(event.payload.count, per_thread, num_shuffles)
        .map(|result| {
            let results: Vec<MeetingTime<u16>> = result.results;

            let failed: HashSet<String> = meeting_ids
                .into_iter()
                .filter(|id| !results.iter().any(|r| r.id == *id))
                .collect();

            Response {
                results,
                failed,
                attempts: result.count,
            }
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
