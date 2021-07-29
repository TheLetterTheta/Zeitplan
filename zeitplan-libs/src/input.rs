use itertools::Itertools;
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::data::{Meeting, Participant, ScheduleMeeting, Time, TimeRange, ValidationError};

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

#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct ScheduleInput {
    pub meetings: HashMap<String, ScheduleMeeting>,
}

impl Default for ScheduleInput {
    fn default() -> Self {
        ScheduleInput {
            meetings: HashMap::new(),
        }
    }
}

impl From<Input> for ScheduleInput {
    fn from(input: Input) -> Self {
        ScheduleInput {
            meetings: input
                .meetings
                .into_iter()
                .map(|(k, v)| (k, v.into()))
                .collect(),
        }
    }
}

impl ScheduleInput {
    pub fn validate(&self) -> Result<(), ValidationError> {
        if self.meetings.len() > 336 {
            Err(ValidationError::UnsupportedLength {
                expected: 336,
                found: self.meetings.len(),
            })
        } else if let Some(m) = self
            .meetings
            .values()
            .find(|m| m.available_times.len() > 336)
        {
            Err(ValidationError::UnsupportedLength {
                expected: 336,
                found: m.available_times.len(),
            })
        } else {
            let (pigeons, pigeon_holes) = self
                .meetings
                .values()
                .filter(|m| !m.available_times.is_empty())
                .fold((0, 0), |acc, n| {
                    (
                        acc.0 + n.duration,
                        acc.1 + n.available_times.iter().map(|m| 1 + m.1 - m.0).sum::<u16>(),
                    )
                });

            if pigeons > pigeon_holes {
                Err(ValidationError::PigeonholeError {
                    pigeons,
                    pigeon_holes,
                })
            } else {
                Ok(())
            }
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
