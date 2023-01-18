use lambda_http::{
    http::StatusCode, run, service_fn, Body, Error, IntoResponse, Request, RequestExt, Response,
};
use std::env;
use zeitplan_libs::schedule::Schedule;

async fn function_handler(event: Request) -> Result<impl IntoResponse, Error> {
    // Extract some useful information from the request
    let resp = Response::builder().header("Content-Type", "application/json");

    Ok(if let Some(schedule) = event.payload::<Schedule<u16>>()? {
        let n_iterations = env::var("EXECUTION_LIMIT")
            .map(|e| e.parse::<usize>().unwrap_or(1))
            .ok();
        resp.status(StatusCode::OK)
            .body(Body::from(serde_json::to_string(
                &schedule.schedule_meetings(n_iterations).map_err(Box::new)?,
            )?))?
    } else {
        resp.status(StatusCode::BAD_REQUEST).body(Body::Empty)?
    })
}

#[tokio::main]
async fn main() -> Result<(), Error> {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        // this needs to be set to false, otherwise ANSI color codes will
        // show up in a confusing manner in CloudWatch logs.
        .with_ansi(false)
        // disabling time is handy because CloudWatch will add the ingestion time.
        .without_time()
        .init();

    run(service_fn(function_handler)).await
}
