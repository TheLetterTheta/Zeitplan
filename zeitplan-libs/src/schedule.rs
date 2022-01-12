use crate::meeting::Meeting;
use crate::time::{Available, Pigeons, TimeMerge, TimeRange, Windowed};
use core::fmt::{Debug, Display};
use num::{CheckedAdd, CheckedSub, Integer, One};
use serde::{Deserialize, Serialize};
use std::cmp::Ordering;
use std::collections::{BTreeMap, HashMap};
use thiserror::Error;

#[derive(Serialize, Error, Debug, Eq, PartialEq)]
pub enum ValidationError<N>
where
    N: Integer + Debug + Display + Debug,
{
    #[error("Trying to schedule {pigeons} meetings in {pigeon_holes} available slots")]
    PigeonholeError { pigeons: N, pigeon_holes: N },
    #[error("Could not find a solution")]
    NoSolution,
}

#[derive(Deserialize)]
pub struct Schedule<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    pub meetings: Vec<Meeting<N>>,
    pub availability: Vec<TimeRange<N>>,
}

type MeetingSchedule<'a, N> = Vec<(String, N, Vec<TimeRange<N>>)>;

impl<N> Schedule<N>
where
    N: Display
        + Debug
        + Integer
        + One
        + Clone
        + Copy
        + std::iter::Sum
        + std::ops::AddAssign
        + CheckedSub
        + CheckedAdd,
{
    /// Constucts a new Schedule to be scheduled
    pub fn new(meetings: Vec<Meeting<N>>, availability: Vec<TimeRange<N>>) -> Schedule<N> {
        Schedule {
            meetings,
            availability,
        }
    }

    fn meeting_availability(&self) -> HashMap<&str, Vec<TimeRange<N>>> {
        self.meetings
            .iter()
            .map(|meeting| {
                (
                    meeting.id.as_str(),
                    meeting.clone().get_availability(&self.availability),
                )
            })
            .collect()
    }

    fn setup(&self) -> Result<MeetingSchedule<N>, ValidationError<N>> {
        let meeting_availability = self.meeting_availability();

        let pigeons: N = self.meetings.iter().map(|m| m.duration).sum();

        let pigeon_holes: N = meeting_availability
            .values()
            .flatten()
            .time_merge()
            .into_iter()
            .collect::<Vec<_>>()
            .iter()
            .count_pigeons();

        if pigeons > pigeon_holes {
            return Err(ValidationError::PigeonholeError {
                pigeons,
                pigeon_holes,
            });
        }

        let result = self
            .meetings
            .iter()
            .filter_map(move |meeting| {
                meeting_availability
                    .get(meeting.id.as_str())
                    .map(|availability| {
                        (meeting.id.clone(), meeting.duration, availability.clone())
                    })
            })
            .collect();
        Ok(result)
    }

    /// Schedules the meetings within self.
    /// The `count` parameter indicates how many solutions to check before giving up.
    /// A `None` value will search all of the possible configurations for a solution.
    ///
    /// # Errors
    /// It is possible to check *some* impossible configurations beforehand. In this
    /// case, a `ValidationError::PigeonholeError { pigeons, pigeon_holes }` will be
    /// returned. This means that we are trying to schedule meetings with less available
    /// times than meetings to be scheduled.
    ///
    /// Otherwise, we iterate for the duration of `count` (or limitless if `None`). If
    /// no solution is found, we return a `ValidationError::NoSolution` error. We currently
    /// make no distinction if `count` was reached, or if all solutions were checked before
    /// the solution was not reached.
    pub fn schedule_meetings(
        &self,
        count: Option<usize>,
    ) -> Result<HashMap<String, TimeRange<N>>, ValidationError<N>> {
        let meetings = self.setup()?;
        let meetings = meetings.into_iter().map(|(id, duration, availability)| {
            (id, duration, availability.iter().windowed(duration))
        });

        let mut nth: usize = 1;
        let mut count_iter: usize = 0;
        let mut state: Vec<usize> = vec![0; self.meetings.len()];
        let mut solution: BTreeMap<InternalTimeRange<N>, String> = BTreeMap::new();
        let mut last_key: Vec<TimeRange<N>> = Vec::with_capacity(self.meetings.len());

        loop {
            if let Some(limit) = count {
                if limit == count_iter {
                    return Err(ValidationError::NoSolution);
                }
                count_iter += 1;
            }

            if meetings.clone().enumerate().skip(nth - 1).all(
                |(index, (meeting_id, _, meeting_times))| match meeting_times
                    .into_iter()
                    .enumerate()
                    .skip(state[index])
                    .find(|(_time_index, time)| {
                        !solution.contains_key::<InternalTimeRange<N>>(&time.into())
                    }) {
                    Some((i, time)) => {
                        state[index] = i;
                        solution.insert(time.into(), meeting_id);
                        last_key.push(time);
                        nth += 1;
                        true
                    }
                    None => {
                        state[index] = 0;
                        if index > 0 {
                            state[index - 1] += 1;
                        }

                        if let Some(last) = last_key.pop() {
                            solution.remove::<InternalTimeRange<N>>(&last.into());
                        }

                        nth -= 1;

                        false
                    }
                },
            ) {
                return Ok(solution
                    .into_iter()
                    .map(|(k, v)| (v, TimeRange::new(k.0, k.1)))
                    .collect());
            }
            if nth == 0 {
                return Err(ValidationError::NoSolution);
            }
        }
    }
}

/// Inclusive [start, end] time range
/// <N>: Any integer type
#[derive(Debug, Copy, Clone, Eq)]
struct InternalTimeRange<N>(pub N, pub N)
where
    N: Integer + One + Copy;

impl<N> From<TimeRange<N>> for InternalTimeRange<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    fn from(other: TimeRange<N>) -> Self {
        InternalTimeRange::new(other.0, other.1)
    }
}

impl<N> From<&TimeRange<N>> for InternalTimeRange<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    fn from(other: &TimeRange<N>) -> Self {
        InternalTimeRange::new(other.0, other.1)
    }
}

impl<N> InternalTimeRange<N>
where
    N: Integer + One + Copy,
{
    fn new(start: N, end: N) -> Self {
        if start > end {
            InternalTimeRange(end, start)
        } else {
            InternalTimeRange(start, end)
        }
    }

    fn start(self) -> N {
        self.0
    }

    fn end(self) -> N {
        self.1
    }
}

impl<N> Ord for InternalTimeRange<N>
where
    N: Integer + Copy,
{
    fn cmp(&self, other: &Self) -> Ordering {
        match self.start().cmp(&other.start()) {
            Ordering::Less if self.end() < other.start() => Ordering::Less,
            Ordering::Greater if self.start() > other.end() => Ordering::Greater,
            _ => Ordering::Equal,
        }
    }
}

impl<N> PartialOrd for InternalTimeRange<N>
where
    N: Integer + Copy,
{
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl<N> PartialEq for InternalTimeRange<N>
where
    N: Integer + Copy,
{
    fn eq(&self, other: &Self) -> bool {
        self.0 == other.0 && self.1 == other.1
    }
}
