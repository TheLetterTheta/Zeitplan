use itertools::Itertools;
use rayon::prelude::*;
use std::cmp::Ordering;
use thiserror::Error;

#[derive(Eq, Debug, Copy, Clone)]
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

#[derive(Clone)]
pub struct Participant {
    pub id: String,
    pub blocked_times: Vec<TimeRange>,
    available_times: Vec<TimeRange>,
}

impl Default for Participant {
    fn default() -> Participant {
        Participant {
            id: String::new(),
            blocked_times: vec![],
            available_times: vec![],
        }
    }
}

impl Participant {
    pub fn new(id: String, blocked_times: Vec<TimeRange>) -> Self {
        Participant {
            id,
            blocked_times,
            available_times: vec![],
        }
    }
}

#[derive(Clone)]
pub struct Meeting {
    pub id: String,
    pub duration: u16,
    pub participant_ids: Vec<String>,
    available_times: Vec<TimeRange>,
}

impl Default for Meeting {
    fn default() -> Meeting {
        Meeting {
            id: String::new(),
            duration: 1,
            participant_ids: vec![],
            available_times: vec![],
        }
    }
}
impl Meeting {
    pub fn new(id: String, duration: u16, participant_ids: Vec<String>) -> Self {
        Meeting {
            id,
            duration,
            participant_ids,
            available_times: vec![],
        }
    }
}

#[derive(Clone)]
pub struct Input {
    pub participants: Vec<Participant>,
    pub meetings: Vec<Meeting>,
    pub available_time_range: Vec<TimeRange>,
    status: Status,
}

#[derive(Clone, Eq)]
enum Status {
    New,
    Validated,
    Sorted,
    FoundUserAvailability,
    FoundMeetingAvailability,
}

impl PartialEq for Status {
    fn eq(&self, other: &Self) -> bool {
        self == other
    }
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
    #[error("Invalid TimeRange found. No duplicate values, nor overlapping entries allowed")]
    OverlappingTimeRange,
}

impl Default for Input {
    fn default() -> Self {
        Input {
            participants: vec![],
            meetings: vec![],
            available_time_range: vec![],
            status: Status::New,
        }
    }
}

impl Input {
    pub fn new(
        participants: Vec<Participant>,
        meetings: Vec<Meeting>,
        available_time_range: Vec<TimeRange>,
    ) -> Self {
        Input {
            participants,
            meetings,
            available_time_range,
            status: Status::New,
        }
    }

    pub fn validate(&mut self) -> Result<(), ValidationError> {
        // There are 336 30-min increments within a week.
        // Assuming we have captured contiguous elements together,
        // this should contain at *most* half of that
        if self.available_time_range.len() > 168 {
            Err(ValidationError::UnsupportedLength {
                expected: 168,
                found: self.available_time_range.len(),
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

        for p in self.participants.iter_mut() {
            if p.blocked_times.len() > 168 {
                return Err(ValidationError::UnsupportedLength {
                    expected: 168,
                    found: p.blocked_times.len(),
                });
            }
            p.blocked_times.par_sort_unstable();

            if p.blocked_times
                .iter()
                .tuple_windows()
                .any(|(i, next)| i.1 >= next.0)
            {
                return Err(ValidationError::OverlappingTimeRange);
            }
        }

        self.available_time_range.par_sort_unstable();

        if self
            .available_time_range
            .iter()
            .tuple_windows()
            .any(|(i, next)| i.1 >= next.0)
        {
            return Err(ValidationError::OverlappingTimeRange);
        }

        self.status = Status::Sorted;
        Ok(())
    }

    pub fn get_user_availability(&mut self) -> Result<(), ValidationError> {
        if self.status == Status::New || self.status == Status::Validated {
            self.sort()?;
        }

        if self.available_time_range.len() == 0 {
            return Ok(());
        }

        let master_iter = self.available_time_range.iter().peekable();

        self.participants.iter_mut().for_each(|mut p| {
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
                self.get_meeting_availability()?;
            }
            _ => {}
        }

        let participants_iter = self.participants.iter();
        self.meetings.iter_mut().for_each(|meeting| {
            let meeting_times = meeting
                .participant_ids
                .iter()
                .map(|u| {
                    participants_iter
                        .clone()
                        .find(|p| &p.id == u)
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
        let mut test_input =
            Input::new(vec![], vec![], (0..300).map(|n| TimeRange(n, n)).collect());

        assert!(match test_input.validate() {
            Err(ValidationError::UnsupportedLength {
                expected: _,
                found: _,
            }) => true,
            _ => false,
        });

        let mut test_input = Input::new(
            (0..200).map(|_| Participant::default()).collect(),
            vec![],
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
            vec![Participant::new(
                "0".to_string(),
                vec![
                    TimeRange(20, 22),
                    TimeRange(1, 3),
                    TimeRange(9, 12),
                    TimeRange(4, 8),
                ],
            )],
            vec![],
            vec![
                TimeRange(20, 22),
                TimeRange(1, 3),
                TimeRange(9, 12),
                TimeRange(4, 8),
            ],
        );

        assert!(test_input.sort().is_ok());

        assert_eq!(
            test_input.participants[0].blocked_times,
            vec![
                TimeRange(1, 3),
                TimeRange(4, 8),
                TimeRange(9, 12),
                TimeRange(20, 22),
            ]
        );
        assert_eq!(
            test_input.available_time_range,
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
            vec![Participant::new(
                "0".to_string(),
                vec![TimeRange(0, 1), TimeRange(1, 1)],
            )],
            vec![],
            vec![],
        );

        assert!(match test_input.sort() {
            Err(ValidationError::OverlappingTimeRange) => true,
            _ => false,
        });

        let mut test_input = Input::new(
            vec![Participant::new(
                "0".to_string(),
                vec![TimeRange(0, 3), TimeRange(1, 5)],
            )],
            vec![],
            vec![],
        );

        assert!(match test_input.sort() {
            Err(ValidationError::OverlappingTimeRange) => true,
            _ => false,
        });

        let mut test_input = Input::new(vec![], vec![], vec![TimeRange(0, 1), TimeRange(1, 1)]);

        assert!(match test_input.sort() {
            Err(ValidationError::OverlappingTimeRange) => true,
            _ => false,
        });
        let mut test_input = Input::new(vec![], vec![], vec![TimeRange(0, 3), TimeRange(1, 5)]);

        assert!(match test_input.sort() {
            Err(ValidationError::OverlappingTimeRange) => true,
            _ => false,
        });
    }

    #[test]
    fn gets_user_availability() {
        let mut test_input = Input::new(
            vec![
                Participant::new(
                    "0".to_string(),
                    vec![TimeRange(0, 0), TimeRange(2, 5), TimeRange(9, 9)],
                ),
                Participant::new(
                    "1".to_string(),
                    vec![TimeRange(1, 1), TimeRange(3, 3), TimeRange(7, 8)],
                ),
                Participant::new("2".to_string(), vec![TimeRange(1, 8)]),
                Participant::new("3".to_string(), vec![]),
                Participant::new("4".to_string(), vec![TimeRange(2, 7)]),
                Participant::new("5".to_string(), vec![TimeRange(9, 9)]),
            ],
            vec![],
            vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)],
        );

        assert!(test_input.sort().is_ok());
        test_input.get_user_availability();

        assert_eq!(
            test_input.participants[0].available_times,
            vec![
                TimeRange(1, 1),
                TimeRange(6, 6),
                TimeRange(8, 8),
                TimeRange(10, 11)
            ]
        );

        assert_eq!(
            test_input.participants[1].available_times,
            vec![TimeRange(0, 0), TimeRange(4, 6), TimeRange(9, 11),]
        );

        assert_eq!(
            test_input.participants[2].available_times,
            vec![TimeRange(0, 0), TimeRange(9, 11),]
        );

        assert_eq!(
            test_input.participants[3].available_times,
            vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)]
        );

        assert_eq!(
            test_input.participants[4].available_times,
            vec![TimeRange(0, 1), TimeRange(8, 11)]
        );

        assert_eq!(
            test_input.participants[5].available_times,
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
                Participant::new(
                    "0".to_string(),
                    vec![TimeRange(0, 0), TimeRange(2, 5), TimeRange(9, 9)],
                ),
                Participant::new(
                    "1".to_string(),
                    vec![TimeRange(1, 1), TimeRange(3, 3), TimeRange(7, 8)],
                ),
                Participant::new("2".to_string(), vec![TimeRange(1, 8)]),
                Participant::new("3".to_string(), vec![]),
                Participant::new("4".to_string(), vec![TimeRange(0, 7)]),
                Participant::new("5".to_string(), vec![TimeRange(8, 12)]),
            ],
            vec![
                Meeting::new("0".to_string(), 1, vec!["0".to_string(), "1".to_string()]),
                Meeting::new("1".to_string(), 2, vec!["0".to_string(), "1".to_string()]),
                Meeting::new("2".to_string(), 1, vec!["1".to_string(), "2".to_string()]),
                Meeting::new(
                    "3".to_string(),
                    1,
                    vec!["0".to_string(), "1".to_string(), "2".to_string()],
                ),
                Meeting::new("4".to_string(), 1, vec!["4".to_string(), "5".to_string()]),
            ],
            vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)],
        );

        assert!(test_input.sort().is_ok());
        test_input.get_user_availability();
        test_input.get_meeting_availability();

        assert_eq!(
            test_input.meetings[0].available_times,
            vec![TimeRange(6, 6), TimeRange(10, 11)]
        );

        assert_eq!(
            test_input.meetings[1].available_times,
            vec![TimeRange(10, 11)]
        );

        assert_eq!(
            test_input.meetings[2].available_times,
            vec![TimeRange(0, 0), TimeRange(9, 11)]
        );

        assert_eq!(
            test_input.meetings[3].available_times,
            vec![TimeRange(10, 11)]
        );

        assert_eq!(test_input.meetings[4].available_times, vec![]);
    }
}
