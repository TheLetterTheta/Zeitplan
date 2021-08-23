use crate::meeting::Meeting;
use itertools::Itertools;
use crate::time::{Available, TimeMerge, Pigeons, TimeRange, Windowed};
use core::fmt::{Debug, Display};
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
pub struct Schedule<'a, N>
where
    N: Integer + One + Copy,
{
    #[serde(bound(deserialize = "Meeting<'a, N>: Deserialize<'de>"))]
    pub meetings: Vec<Meeting<'a, N>>,
    pub availability: Vec<TimeRange<N>>,
}

type MeetingSchedule<'a, N> = Vec<(&'a str, Vec<TimeRange<N>>)>;

impl<'a, N> Schedule<'a, N>
where
    N: Display + Debug + Integer + One + Clone + Copy + std::iter::Sum,
{
    pub fn new(meetings: Vec<Meeting<'a, N>>, availability: Vec<TimeRange<N>>) -> Schedule<'a, N> {
        Schedule {
            meetings,
            availability,
        }
    }

    fn windowed(&self, meetings: HashMap<&str, Vec<TimeRange<N>>>) -> MeetingSchedule<N> {
        self.meetings
            .iter()
            .filter_map(|meeting| {
                meetings.get(meeting.id).map(|availability| {
                    (meeting.id, availability.iter().windowed(meeting.duration))
                })
            })
            .collect()
    }

    fn meeting_availability(&self) -> HashMap<&str, Vec<TimeRange<N>>> {
        self.meetings
            .iter()
            .map(|meeting| {
                (
                    meeting.id,
                    meeting.clone().get_availability(&self.availability),
                )
            })
            .collect()
    }

    fn setup(&self) -> Result<MeetingSchedule<N>, ValidationError<N>> {
        let meeting_availability = self.meeting_availability();

        let pigeons : N = self.meetings.iter().map(|m| m.duration).sum();

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

        let mut meetings = self.windowed(meeting_availability);
        meetings.sort_unstable_by_key(|(_id, availability)| availability.len());
        Ok(meetings)
    }

    pub fn schedule_meetings(
        &self,
        count: Option<usize>,
    ) -> Result<BTreeMap<TimeRange<N>, &str>, ValidationError<N>> {
        let meetings = self.setup()?;

        let mut nth: usize = 1;
        let mut count_iter: usize = 0;
        let mut state: Vec<usize> = vec![0; meetings.len()];
        let mut solution: BTreeMap<TimeRange<N>, &str> = BTreeMap::new();
        let mut last_key: Vec<TimeRange<N>> = Vec::with_capacity(meetings.len());

        loop {
            if let Some(limit) = count {
                if limit == count_iter {
                    return Err(ValidationError::NoSolution);
                }
                count_iter += 1;
            }

            if meetings.iter().enumerate().skip(nth - 1).all(
                |(index, (meeting_id, meeting_times))| match meeting_times
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
