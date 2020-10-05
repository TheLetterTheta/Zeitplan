#![cfg_attr(
  all(not(debug_assertions), target_os = "windows"),
  windows_subsystem = "windows"
)]

mod cmd;
use rayon::prelude::*;
use serde::Serialize;
use sled::Config;
use std::error::Error;
use std::sync::Arc;
use tauri_api::path::data_dir;

#[derive(Debug, Serialize)]
pub struct MeetingTimeslots {
  pub id: String,
  pub timeslots: Vec<cmd::MeetingTimeslot>,
}

fn main() -> Result<(), Box<dyn Error>> {
  let mut dir = data_dir().unwrap();
  dir.push("zeitplan");
  let config = Config::new().path(dir).flush_every_ms(Some(4000));
  let conn = Arc::from(config.open()?);

  tauri::AppBuilder::new()
    .invoke_handler(move |_webview, arg| {
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
            } => tauri::execute_promise(_webview, move || Ok(payload.compute()), callback, error),
            ComputeMeetingSpace {
              payload,
              callback,
              error,
            } => tauri::execute_promise(
              _webview,
              move || {
                let times = payload.get_meeting_availability();
                Ok(
                  times
                    .into_par_iter()
                    .map(|v| MeetingTimeslots {
                      id: v.id,
                      timeslots: match v.available_times {
                        Some(times) => {
                          cmd::check_timespan_duration(times.into_iter().collect(), v.duration)
                        }
                        None => Vec::new(),
                      },
                    })
                    .collect::<Vec<_>>(),
                )
              },
              callback,
              error,
            ),
            ComputeAllMeetingCombinations {
              payload,
              callback,
              error,
            } => tauri::execute_promise(
              _webview,
              move || Ok(payload.compute_all_possible_timespans()),
              callback,
              error,
            ),
            GetKey {
              payload,
              callback,
              error,
            } => {
              let db = conn.clone();
              tauri::execute_promise(
                _webview,
                move || match db.get(payload.as_bytes())? {
                  Some(v) => Ok(String::from_utf8(Vec::from(v.as_ref()))?),
                  None => Ok(String::new()),
                },
                callback,
                error,
              )
            }
            SetKey {
              payload,
              callback,
              error,
            } => {
              let db = conn.clone();
              tauri::execute_promise(
                _webview,
                move || {
                  db.insert(payload.key.as_bytes(), payload.value.as_bytes())?;
                  Ok(())
                },
                callback,
                error,
              )
            }
            DeleteKey {
              payload,
              callback,
              error,
            } => {
              let db = conn.clone();
              tauri::execute_promise(
                _webview,
                move || {
                  db.remove(payload.as_bytes())?;
                  Ok(())
                },
                callback,
                error,
              )
            }
          }
          Ok(())
        }
      }
    })
    .build()
    .run();

  Ok(())
}
