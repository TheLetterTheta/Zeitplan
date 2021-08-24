use crate::meeting::Meeting;
use crate::time::{Available, Pigeons, TimeMerge, TimeRange, Windowed};
use core::fmt::{Debug, Display};
use itertools::Itertools;
use num::{Integer, One};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use thiserror::Error;

#[derive(Serialize, Error, Debug, Eq, PartialEq)]
pub enum ValidationError<N>
where
    N: Integer + Debug + Display,
{
    #[error("Trying to schedule {pigeons} meetings in {pigeon_holes} available slots")]
    PigeonholeError { pigeons: N, pigeon_holes: N },
    #[error("Could not find a solution")]
    NoSolution,
}

#[derive(Serialize, Deserialize)]
pub struct Schedule<N>
where
    N: Integer + One + Copy,
{
    pub meetings: Vec<Meeting<N>>,
    pub availability: Vec<TimeRange<N>>,
}

type MeetingSchedule<'a, N> = Vec<(String, N, Vec<TimeRange<N>>)>;

impl<N> Schedule<N>
where
    N: Display + Debug + Integer + One + Clone + Copy + std::iter::Sum + std::ops::AddAssign,
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
            .sorted_unstable()
            .time_merge()
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
    ) -> Result<BTreeMap<TimeRange<N>, String>, ValidationError<N>> {
        let meetings = self.setup()?;
        let meetings = meetings.into_iter().map(|(id, duration, availability)| {
            (id, duration, availability.iter().windowed(duration))
        });

        let mut nth: usize = 1;
        let mut count_iter: usize = 0;
        let mut state: Vec<usize> = vec![0; self.meetings.len()];
        let mut solution: BTreeMap<TimeRange<N>, String> = BTreeMap::new();
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
                    .iter()
                    .enumerate()
                    .skip(state[index])
                    .find(|(_time_index, time)| !solution.contains_key(*time))
                {
                    Some((i, time)) => {
                        state[index] = i;
                        solution.insert(*time, meeting_id);
                        last_key.push(*time);
                        nth += 1;
                        true
                    }
                    None => {
                        state[index] = 0;
                        if index > 0 {
                            state[index - 1] += 1;
                        }

                        if let Some(last) = last_key.pop() {
                            solution.remove(&last);
                        }

                        nth -= 1;

                        false
                    }
                },
            ) {
                return Ok(solution);
            }
            if nth == 0 {
                return Err(ValidationError::NoSolution);
            }
        }
    }
}
