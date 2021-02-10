use itertools::Itertools;
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::cmp::Ordering;
use std::collections::HashMap;
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
        self.0 == other.0
    }
}

impl Ord for TimeRange {
    fn cmp(&self, other: &Self) -> Ordering {
        self.0.cmp(&other.0)
    }
}

#[derive(Clone, Serialize, Deserialize)]
pub struct Participant {
    #[serde(rename = "blockedTimes")]
    pub blocked_times: Vec<TimeRange>,
    #[serde(skip)]
    available_times: Vec<TimeRange>,
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
    available_times: Vec<TimeRange>,
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

#[derive(Clone, PartialEq, Eq)]
enum Status {
    New,
    Validated,
    Sorted,
    FoundUserAvailability,
    FoundMeetingAvailability,
}

#[derive(Eq)]
enum Time {
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

#[derive(Error, Debug)]
pub enum ValidationError {
    #[error("Unsupported length of input. Expected {expected}, got {found}")]
    UnsupportedLength { expected: usize, found: usize },
    #[error("Invalid TimeRange found. No duplicate values, nor overlapping entries allowed\n{location} received {value}")]
    OverlappingTimeRange { location: String, value: u16 },
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Input {
    pub participants: HashMap<String, Participant>,
    pub meetings: HashMap<String, Meeting>,
    #[serde(rename = "availableTimes")]
    pub available_times: Vec<TimeRange>,
    #[serde(skip)]
    status: Status,
}

impl Default for Input {
    fn default() -> Self {
        Input {
            participants: HashMap::new(),
            meetings: HashMap::new(),
            available_times: vec![],
            status: Status::New,
        }
    }
}

impl Input {
    pub fn new(
        participants: HashMap<String, Participant>,
        meetings: HashMap<String, Meeting>,
        available_times: Vec<TimeRange>,
    ) -> Self {
        Input {
            participants,
            meetings,
            available_times,
            status: Status::New,
        }
    }

    pub fn validate(&mut self) -> Result<(), ValidationError> {
        // There are 336 30-min increments within a week.
        // Assuming we have captured contiguous elements together,
        // this should contain at *most* half of that
        if self.available_times.len() > 168 {
            Err(ValidationError::UnsupportedLength {
                expected: 168,
                found: self.available_times.len(),
            })
        } else if self.participants.len() > 100 {
            Err(ValidationError::UnsupportedLength {
                expected: 100,
                found: self.participants.len(),
            })
        } else {
            self.status = Status::Validated;

            Ok(())
        }
    }

    pub fn sort(&mut self) -> Result<(), ValidationError> {
        if self.status == Status::New {
            self.validate()?;
        }

        for (k, p) in self.participants.iter_mut() {
            if p.blocked_times.len() > 168 {
                return Err(ValidationError::UnsupportedLength {
                    expected: 168,
                    found: p.blocked_times.len(),
                });
            }
            p.blocked_times.par_sort_unstable();

            if let Some((_, next)) = p
                .blocked_times
                .iter()
                .tuple_windows()
                .find(|(i, next)| i.1 >= next.0)
            {
                return Err(ValidationError::OverlappingTimeRange {
                    location: format!("Participant ({})", k),
                    value: next.0,
                });
            }
        }

        self.available_times.par_sort_unstable();

        if let Some((_, next)) = self
            .available_times
            .iter()
            .tuple_windows()
            .find(|(i, next)| i.1 >= next.0)
        {
            return Err(ValidationError::OverlappingTimeRange {
                location: "Available time range".to_string(),
                value: next.0,
            });
        }

        self.status = Status::Sorted;

        Ok(())
    }

    pub fn get_user_availability(&mut self) -> Result<(), ValidationError> {
        if self.status == Status::New || self.status == Status::Validated {
            self.sort()?;
        }

        if self.available_times.len() == 0 {
            return Ok(());
        }

        let master_iter = self.available_times.iter().peekable();

        self.participants.values_mut().for_each(|mut p| {
            if p.blocked_times.len() == 0 {
                p.available_times = master_iter.clone().map(|p| p.to_owned()).collect();
                return;
            }

            let mut available_iter = { master_iter.clone() };
            let mut blocked_iter = p.blocked_times.iter().peekable();

            let mut available_times = Vec::new();

            'outer: while let Some(available) = &available_iter.next() {
                let mut start = available.0;
                let end = available.1;

                while let Some(&&TimeRange(block_start, block_end)) = blocked_iter.peek() {
                    // The next block is already outside of the range we care about, nothing to
                    // block here.
                    if block_start > end {
                        break;
                    }

                    if block_end >= start {
                        // We need to close of the current block.
                        if start < block_start {
                            available_times.push(TimeRange(start, block_start - 1));
                        }

                        // Otherwise, we need to bump the start time
                        start = block_end + 1;

                        // And increment our iterator again
                        if end < start {
                            while let Some(&&TimeRange(_, consume_end)) = available_iter.peek() {
                                if start > consume_end {
                                    available_iter.next();
                                } else {
                                    break;
                                }
                            }
                            continue 'outer;
                        }
                    }

                    blocked_iter.next();
                }

                available_times.push(TimeRange(start, end));
            }

            p.available_times = available_times;
        });

        self.status = Status::FoundUserAvailability;

        Ok(())
    }

    pub fn get_meeting_availability(&mut self) -> Result<(), ValidationError> {
        match self.status {
            Status::New | Status::Sorted | Status::Validated => {
                self.get_user_availability()?;
            }
            _ => {}
        }

        let participants = &self.participants;
        self.meetings.values_mut().for_each(|meeting| {
            let meeting_times = meeting
                .participant_ids
                .iter()
                .map(|u| {
                    participants
                        .get(u)
                        .expect("Invalid participant id")
                        .available_times
                        .iter()
                        .flat_map(|t| vec![Time::Start(t.0), Time::End(t.1)])
                })
                .kmerge();

            let mut iter_stack = Vec::with_capacity(meeting.participant_ids.len());
            for time in meeting_times.into_iter() {
                match time {
                    Time::Start(t) => iter_stack.push(t),
                    Time::End(t) => {
                        if let Some(last) = iter_stack.pop() {
                            if iter_stack.len() == meeting.participant_ids.len() - 1
                                && t - last >= (meeting.duration - 1)
                            {
                                meeting.available_times.push(TimeRange(last, t))
                            }
                        }
                    }
                }
            }
        });

        self.status = Status::FoundMeetingAvailability;

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use crate::*;
    #[test]
    fn validates_invalid_input() {
        let mut test_input = Input::new(
            HashMap::new(),
            HashMap::new(),
            (0..300).map(|n| TimeRange(n, n)).collect(),
        );

        assert!(match test_input.validate() {
            Err(ValidationError::UnsupportedLength {
                expected: _,
                found: _,
            }) => true,
            _ => false,
        });

        let mut test_input = Input::new(
            (0..200)
                .map(|n| (n.to_string(), Participant::default()))
                .collect(),
            HashMap::new(),
            vec![],
        );

        assert!(match test_input.validate() {
            Err(ValidationError::UnsupportedLength {
                expected: _,
                found: _,
            }) => true,
            _ => false,
        });
    }

    #[test]
    fn sort_input_works() {
        let mut test_input = Input::new(
            vec![(
                "0".to_string(),
                Participant::new(vec![
                    TimeRange(20, 22),
                    TimeRange(1, 3),
                    TimeRange(9, 12),
                    TimeRange(4, 8),
                ]),
            )]
            .into_iter()
            .collect(),
            HashMap::new(),
            vec![
                TimeRange(20, 22),
                TimeRange(1, 3),
                TimeRange(9, 12),
                TimeRange(4, 8),
            ],
        );

        assert!(test_input.sort().is_ok());

        assert_eq!(
            test_input.participants.get("0").unwrap().blocked_times,
            vec![
                TimeRange(1, 3),
                TimeRange(4, 8),
                TimeRange(9, 12),
                TimeRange(20, 22),
            ]
        );
        assert_eq!(
            test_input.available_times,
            vec![
                TimeRange(1, 3),
                TimeRange(4, 8),
                TimeRange(9, 12),
                TimeRange(20, 22),
            ]
        );
    }

    #[test]
    fn sort_input_validation() {
        let mut test_input = Input::new(
            vec![(
                "0".to_string(),
                Participant::new(vec![TimeRange(0, 1), TimeRange(1, 1)]),
            )]
            .into_iter()
            .collect(),
            HashMap::new(),
            vec![],
        );

        assert!(match test_input.sort() {
            Err(ValidationError::OverlappingTimeRange {
                location: _,
                value: _,
            }) => true,
            _ => false,
        });

        let mut test_input = Input::new(
            vec![(
                "0".to_string(),
                Participant::new(vec![TimeRange(0, 3), TimeRange(1, 5)]),
            )]
            .into_iter()
            .collect(),
            HashMap::new(),
            vec![],
        );

        assert!(match test_input.sort() {
            Err(ValidationError::OverlappingTimeRange {
                location: _,
                value: _,
            }) => true,
            _ => false,
        });

        let mut test_input = Input::new(
            HashMap::new(),
            HashMap::new(),
            vec![TimeRange(0, 1), TimeRange(1, 1)],
        );

        assert!(match test_input.sort() {
            Err(ValidationError::OverlappingTimeRange {
                location: _,
                value: _,
            }) => true,
            _ => false,
        });
        let mut test_input = Input::new(
            HashMap::new(),
            HashMap::new(),
            vec![TimeRange(0, 3), TimeRange(1, 5)],
        );

        assert!(match test_input.sort() {
            Err(ValidationError::OverlappingTimeRange {
                location: _,
                value: _,
            }) => true,
            _ => false,
        });
    }

    #[test]
    fn gets_user_availability() {
        let mut test_input = Input::new(
            vec![
                (
                    "0".to_string(),
                    Participant::new(vec![TimeRange(0, 0), TimeRange(2, 5), TimeRange(9, 9)]),
                ),
                (
                    "1".to_string(),
                    Participant::new(vec![TimeRange(1, 1), TimeRange(3, 3), TimeRange(7, 8)]),
                ),
                ("2".to_string(), Participant::new(vec![TimeRange(1, 8)])),
                ("3".to_string(), Participant::new(vec![])),
                ("4".to_string(), Participant::new(vec![TimeRange(2, 7)])),
                ("5".to_string(), Participant::new(vec![TimeRange(9, 9)])),
            ]
            .into_iter()
            .collect(),
            HashMap::new(),
            vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)],
        );

        assert!(test_input.sort().is_ok());
        test_input.get_user_availability();

        assert_eq!(
            test_input.participants.get("0").unwrap().available_times,
            vec![
                TimeRange(1, 1),
                TimeRange(6, 6),
                TimeRange(8, 8),
                TimeRange(10, 11)
            ]
        );

        assert_eq!(
            test_input.participants.get("1").unwrap().available_times,
            vec![TimeRange(0, 0), TimeRange(4, 6), TimeRange(9, 11),]
        );

        assert_eq!(
            test_input.participants.get("2").unwrap().available_times,
            vec![TimeRange(0, 0), TimeRange(9, 11),]
        );

        assert_eq!(
            test_input.participants.get("3").unwrap().available_times,
            vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)]
        );

        assert_eq!(
            test_input.participants.get("4").unwrap().available_times,
            vec![TimeRange(0, 1), TimeRange(8, 11)]
        );

        assert_eq!(
            test_input.participants.get("5").unwrap().available_times,
            vec![
                TimeRange(0, 1),
                TimeRange(3, 6),
                TimeRange(8, 8),
                TimeRange(10, 11)
            ]
        );
    }

    #[test]
    fn gets_meeting_availability() {
        let mut test_input = Input::new(
            vec![
                (
                    "0".to_string(),
                    Participant::new(vec![TimeRange(0, 0), TimeRange(2, 5), TimeRange(9, 9)]),
                ),
                (
                    "1".to_string(),
                    Participant::new(vec![TimeRange(1, 1), TimeRange(3, 3), TimeRange(7, 8)]),
                ),
                ("2".to_string(), Participant::new(vec![TimeRange(1, 8)])),
                ("3".to_string(), Participant::new(vec![])),
                ("4".to_string(), Participant::new(vec![TimeRange(0, 7)])),
                ("5".to_string(), Participant::new(vec![TimeRange(8, 12)])),
            ]
            .into_iter()
            .collect(),
            vec![
                (
                    "0".to_string(),
                    Meeting::new(1, vec!["0".to_string(), "1".to_string()]),
                ),
                (
                    "1".to_string(),
                    Meeting::new(2, vec!["0".to_string(), "1".to_string()]),
                ),
                (
                    "2".to_string(),
                    Meeting::new(1, vec!["1".to_string(), "2".to_string()]),
                ),
                (
                    "3".to_string(),
                    Meeting::new(1, vec!["0".to_string(), "1".to_string(), "2".to_string()]),
                ),
                (
                    "4".to_string(),
                    Meeting::new(1, vec!["4".to_string(), "5".to_string()]),
                ),
            ]
            .into_iter()
            .collect(),
            vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)],
        );

        assert!(test_input.sort().is_ok());
        test_input.get_user_availability();
        test_input.get_meeting_availability();

        assert_eq!(
            test_input.meetings.get("0").unwrap().available_times,
            vec![TimeRange(6, 6), TimeRange(10, 11)]
        );

        assert_eq!(
            test_input.meetings.get("1").unwrap().available_times,
            vec![TimeRange(10, 11)]
        );

        assert_eq!(
            test_input.meetings.get("2").unwrap().available_times,
            vec![TimeRange(0, 0), TimeRange(9, 11)]
        );

        assert_eq!(
            test_input.meetings.get("3").unwrap().available_times,
            vec![TimeRange(10, 11)]
        );

        assert_eq!(
            test_input.meetings.get("4").unwrap().available_times,
            vec![]
        );
    }
}
