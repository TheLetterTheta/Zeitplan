use itertools::Itertools;
use rayon::prelude::*;
use serde::{Deserialize, Serialize};
use std::cmp::Ordering;

#[derive(Eq, Deserialize, Serialize, Debug, Copy, Clone)]
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

#[derive(Deserialize, Clone, Serialize)]
pub struct Participant {
    pub id: String,
    pub blocked_times: Vec<TimeRange>,
    pub available_times: Vec<TimeRange>,
}

#[derive(Deserialize, Clone, Serialize)]
pub struct Meeting {
    pub id: String,
    pub duration: u16,
    pub participant_ids: Vec<String>,
    pub available_times: Vec<TimeRange>,
}

#[derive(Deserialize, Clone, Serialize)]
pub struct Input {
    pub participants: Vec<Participant>,
    pub meetings: Vec<Meeting>,
    pub available_time_range: Vec<TimeRange>,
    pub is_sorted: bool,
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

impl Input {
    pub fn sort(&mut self) {
        self.participants
            .iter_mut()
            .for_each(|p| p.blocked_times.par_sort_unstable());

        self.available_time_range.par_sort_unstable();

        self.is_sorted = true;
    }

    pub fn get_user_availability(&mut self) {
        assert!(self.is_sorted);

        if self.available_time_range.len() == 0 {
            return;
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
    }

    pub fn get_meeting_availability(&mut self) {
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
    }
}

#[cfg(test)]
mod tests {
    use crate::*;

    #[test]
    fn sort_input_works() {
        let mut test_input = Input {
            participants: vec![Participant {
                id: "0".to_string(),
                blocked_times: vec![
                    TimeRange(20, 22),
                    TimeRange(1, 3),
                    TimeRange(9, 12),
                    TimeRange(4, 8),
                ],
                available_times: vec![],
            }],
            meetings: vec![],
            available_time_range: vec![
                TimeRange(20, 22),
                TimeRange(1, 3),
                TimeRange(9, 12),
                TimeRange(4, 8),
            ],
            is_sorted: false,
        };

        test_input.sort();

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
    fn gets_user_availability() {
        let mut test_input = Input {
            participants: vec![
                Participant {
                    id: "0".to_string(),
                    blocked_times: vec![TimeRange(0, 0), TimeRange(2, 5), TimeRange(9, 9)],
                    available_times: vec![],
                },
                Participant {
                    id: "1".to_string(),
                    blocked_times: vec![TimeRange(1, 1), TimeRange(3, 3), TimeRange(7, 8)],
                    available_times: vec![],
                },
                Participant {
                    id: "2".to_string(),
                    blocked_times: vec![TimeRange(1, 8)],
                    available_times: vec![],
                },
                Participant {
                    id: "3".to_string(),
                    blocked_times: vec![],
                    available_times: vec![],
                },
                Participant {
                    id: "4".to_string(),
                    blocked_times: vec![TimeRange(2, 7)],
                    available_times: vec![],
                },
                Participant {
                    id: "5".to_string(),
                    blocked_times: vec![TimeRange(9, 9)],
                    available_times: vec![],
                },
            ],
            meetings: vec![],
            available_time_range: vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)],
            is_sorted: false,
        };

        test_input.sort();
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
        let mut test_input = Input {
            participants: vec![
                Participant {
                    id: "0".to_string(),
                    blocked_times: vec![TimeRange(0, 0), TimeRange(2, 5), TimeRange(9, 9)],
                    available_times: vec![],
                },
                Participant {
                    id: "1".to_string(),
                    blocked_times: vec![TimeRange(1, 1), TimeRange(3, 3), TimeRange(7, 8)],
                    available_times: vec![],
                },
                Participant {
                    id: "2".to_string(),
                    blocked_times: vec![TimeRange(1, 8)],
                    available_times: vec![],
                },
                Participant {
                    id: "3".to_string(),
                    blocked_times: vec![],
                    available_times: vec![],
                },
                Participant {
                    id: "4".to_string(),
                    blocked_times: vec![TimeRange(2, 7)],
                    available_times: vec![],
                },
                Participant {
                    id: "5".to_string(),
                    blocked_times: vec![TimeRange(9, 9)],
                    available_times: vec![],
                },
            ],
            meetings: vec![Meeting {
                id: "0".to_string(),
                duration: 1,
                participant_ids: vec!["0".to_string(), "1".to_string()],
                available_times: vec![],
            }],
            available_time_range: vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)],
            is_sorted: false,
        };

        test_input.sort();
        test_input.get_user_availability();
        test_input.get_meeting_availability();

        assert_eq!(
            test_input.meetings[0].available_times,
            vec![TimeRange(6, 6), TimeRange(10, 11)]
        )
    }
}
