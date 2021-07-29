use serde::{Deserialize, Serialize};
use std::cmp::Ordering;
use thiserror::Error;

#[derive(Eq, Debug, Copy, Clone, Serialize, Deserialize)]
pub struct TimeRange(pub u16, pub u16);

impl PartialOrd for TimeRange {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl PartialEq for TimeRange {
    fn eq(&self, other: &Self) -> bool {
        self == other
    }
}

impl Ord for TimeRange {
    fn cmp(&self, other: &Self) -> Ordering {
        match self.0.cmp(&other.0) {
            Ordering::Greater if other.1 < self.0 => Ordering::Greater,
            Ordering::Less if self.1 < other.0 => Ordering::Less,
            _ => Ordering::Equal,
        }
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub struct Participant {
    #[serde(rename = "blockedTimes")]
    pub blocked_times: Vec<TimeRange>,
    #[serde(skip)]
    pub available_times: Vec<TimeRange>,
}

impl Default for Participant {
    fn default() -> Participant {
        Participant {
            blocked_times: vec![],
            available_times: vec![],
        }
    }
}

impl Participant {
    pub fn new(blocked_times: Vec<TimeRange>) -> Self {
        Participant {
            blocked_times,
            available_times: vec![],
        }
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub struct Meeting {
    pub duration: u16,
    #[serde(rename = "participantIds")]
    pub participant_ids: Vec<String>,
    #[serde(skip_deserializing, rename = "availableTimes")]
    pub available_times: Vec<TimeRange>,
}

impl Default for Meeting {
    fn default() -> Meeting {
        Meeting {
            duration: 1,
            participant_ids: vec![],
            available_times: vec![],
        }
    }
}
impl Meeting {
    pub fn new(duration: u16, participant_ids: Vec<String>) -> Self {
        Meeting {
            duration,
            participant_ids,
            available_times: vec![],
        }
    }
}

#[derive(Eq)]
pub enum Time {
    Start(u16),
    End(u16),
}

impl PartialOrd for Time {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl PartialEq for Time {
    fn eq(&self, other: &Self) -> bool {
        self == other
    }
}

impl Ord for Time {
    fn cmp(&self, other: &Self) -> Ordering {
        match self {
            Time::Start(s) => match other {
                Time::Start(o) => s.cmp(o),
                Time::End(e) => {
                    if s <= e {
                        Ordering::Less
                    } else {
                        Ordering::Greater
                    }
                }
            },
            Time::End(e) => match other {
                Time::Start(s) => {
                    if e >= s {
                        Ordering::Greater
                    } else {
                        Ordering::Less
                    }
                }
                Time::End(s) => e.cmp(s),
            },
        }
    }
}

#[derive(Error, Debug, Eq, PartialEq)]
pub enum ValidationError {
    #[error("Unsupported length of input. Expected {expected}, got {found}")]
    UnsupportedLength { expected: usize, found: usize },
    #[error("Invalid TimeRange found. No duplicate values, nor overlapping entries allowed\n{location} received {value}")]
    OverlappingTimeRange { location: String, value: u16 },
    #[error("Trying to schedule {pigeons} meetings in {pigeon_holes} available slots")]
    PigeonholeError { pigeons: u16, pigeon_holes: u16 },
    #[error("Could not find a solution")]
    NoSolution,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ScheduleMeeting {
    pub duration: u16,
    #[serde(rename = "availableTimes")]
    pub available_times: Vec<TimeRange>,
}

impl From<Meeting> for ScheduleMeeting {
    fn from(input: Meeting) -> Self {
        ScheduleMeeting {
            duration: input.duration,
            available_times: input.available_times,
        }
    }
}

impl Default for ScheduleMeeting {
    fn default() -> Self {
        ScheduleMeeting {
            duration: 0,
            available_times: Vec::new(),
        }
    }
}
