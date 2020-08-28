#![cfg_attr(
    all(not(debug_assertions), target_os = "windows"),
    windows_subsystem = "windows"
)]

mod cmd;
use rayon::prelude::*;
use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct MeetingTimeslots {
    pub id: String,
    pub timeslots: Vec<cmd::MeetingTimeslot>,
}

fn main() {
    tauri::AppBuilder::new()
        .invoke_handler(|_webview, arg| {
            use cmd::Cmd::*;
            match serde_json::from_str(arg) {
                Err(e) => Err(e.to_string()),
                Ok(command) => {
                    match command {
                        // definitions for your custom commands from Cmd here
                        ComputeScheduleFromMeetings {
                            payload,
                            callback,
                            error,
                        } => tauri::execute_promise(
                            _webview,
                            move || Ok(payload.compute()),
                            callback,
                            error,
                            ),
                            ComputeMeetingSpace {
                                payload,
                                callback,
                                error,
                            } => tauri::execute_promise(
                                _webview,
                                move || {
                                    let times = payload.get_meeting_availability();
                                    Ok(times
                                       .into_par_iter()
                                       .filter(|v| v.available_times.is_some())
                                       .map(|v|
                                            MeetingTimeslots {
                                                id: v.id,
                                                timeslots: cmd::check_timespan_duration(v.available_times.unwrap().into_iter().collect(), v.duration)
                                            }
                                           )
                                        .collect::<Vec<_>>())
                                },
                                callback,
                                error,
                                ),
                    }
                    Ok(())
                }
            }
        })
    .build()
        .run();
}
