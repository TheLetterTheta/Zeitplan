use serde::Deserialize;

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct User {
    id: String,
    events: Vec::<u16>,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Meeting {
    id: String,
    duration: u8,
    participant_ids: Vec<String>,
    title: String,
}


#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ComputeMeetingSpacePayload {
    users: Vec<User>,
    meetings: Vec<Meeting>,
    available_time_range: Vec<u16>
}

#[derive(Deserialize)]
#[serde(tag = "cmd", rename_all = "camelCase")]
pub enum Cmd {
  // your custom commands
  // multiple arguments are allowed
  // note that rename_all = "camelCase": you need to use "myCustomCommand" on JS
  ComputeMeetingSpace { payload: ComputeMeetingSpacePayload , callback: String, error: String},
}
