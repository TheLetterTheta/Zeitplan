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

#[derive(Deserialize, Debug)]
pub struct Schedule<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    pub meetings: Vec<Meeting<N>>,
    pub availability: Vec<TimeRange<N>>,
}

#[cfg(feature = "arbitrary")]
impl<'a, N> arbitrary::Arbitrary<'a> for Schedule<N>
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
        + CheckedAdd
        + arbitrary::Arbitrary<'a>,
{
    fn arbitrary(u: &mut arbitrary::Unstructured<'a>) -> arbitrary::Result<Self> {
        let len = u.arbitrary_len::<usize>()?.min(1);
        let mut meetings = Vec::with_capacity(len);
        for _ in 0..len {
            meetings.push(u.arbitrary::<Meeting<N>>()?);
        }
        let mut availability = u.arbitrary::<Vec<TimeRange<N>>>()?;
        if availability.len() == 0 {
            availability.push(u.arbitrary::<TimeRange<N>>()?);
        }
        Ok(Schedule::new(meetings, availability))
    }
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

        // Duration - 1 because pigeon_holes is zero based
        let pigeons: N = self.meetings.iter().map(|m| m.duration).sum();

        if let Some(pigeon_holes) = meeting_availability
            .values()
            .flatten()
            .time_merge()
            .count_pigeons()
        {
            if pigeons > pigeon_holes {
                return Err(ValidationError::PigeonholeError {
                    pigeons,
                    pigeon_holes,
                });
            }
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
    /// # Pigeonhole Error Example
    /// ```
    /// use zeitplan_libs::{
    ///     meeting::Meeting,
    ///     participant::Participant,
    ///     schedule::{Schedule, ValidationError},
    ///     time::TimeRange,
    /// };
    ///
    /// // 105 possible timeslots
    /// let available_slots: Vec<TimeRange<u8>> = vec![
    ///     TimeRange::new(0, 100),
    ///     TimeRange::new(200, 200),
    ///     TimeRange::new(201, 203),
    /// ];
    ///
    /// let mut meetings = Vec::with_capacity(106);
    ///
    /// // We create 106 meetings
    /// for i in 0..106_u8 {
    ///     // No blocked times in each participant
    ///     let participant = Participant::new(&i.to_string(), vec![]);
    ///
    ///     // This meeting's duration is 1
    ///     meetings.push(Meeting::new(&i.to_string(), vec![participant], 1));
    /// }
    ///
    /// let schedule = Schedule::new(meetings, available_slots);
    ///
    /// match schedule.schedule_meetings(None) {
    ///     Err(ValidationError::PigeonholeError {
    ///         pigeons,
    ///         pigeon_holes,
    ///     }) => {
    ///         assert_eq!(pigeons, 106);
    ///         assert_eq!(pigeon_holes, 105);
    ///     },
    ///     _ => panic!("This did not result in a PigeonholeError")
    /// };
    ///
    /// ```
    ///
    /// Pigeons are counted after being trimmed:
    /// ```
    /// use zeitplan_libs::{
    ///     meeting::Meeting,
    ///     participant::Participant,
    ///     schedule::{Schedule, ValidationError},
    ///     time::TimeRange,
    /// };
    ///
    /// // 106 possible timeslots
    /// let available_slots: Vec<TimeRange<u8>> = vec![
    ///     TimeRange::new(0, 100),
    ///     TimeRange::new(200, 200),
    ///     TimeRange::new(201, 203),
    ///     TimeRange::new(150, 150), // This one - however - is not available to any!
    /// ];
    ///
    /// let mut meetings = Vec::with_capacity(106);
    ///
    /// // We create 106 meetings
    /// for i in 0..106_u8 {
    ///     // Only block off the common time
    ///     let participant = Participant::new(&i.to_string(), vec![TimeRange::new(150, 150)]);
    ///
    ///     // This meeting's duration is 1
    ///     meetings.push(Meeting::new(&i.to_string(), vec![participant], 1));
    /// }
    ///
    /// let schedule = Schedule::new(meetings, available_slots);
    ///
    /// match schedule.schedule_meetings(None) {
    ///     Err(ValidationError::PigeonholeError {
    ///         pigeons,
    ///         pigeon_holes,
    ///     }) => {
    ///         assert_eq!(pigeons, 106);
    ///         assert_eq!(pigeon_holes, 105); // TODO: This test fails... Find out why
    ///     },
    ///     _ => panic!("This did not result in a PigeonholeError")
    /// };
    /// ```
    ///
    /// Otherwise, we iterate for the duration of `count` (or limitless if `None`). If
    /// no solution is found, we return a `ValidationError::NoSolution` error. We currently
    /// make no distinction if `count` was reached, or if all solutions were checked before
    /// the solution was not reached.
    ///
    /// # NoSolution Error Example
    /// ```
    /// use zeitplan_libs::{
    ///     meeting::Meeting,
    ///     participant::Participant,
    ///     schedule::{Schedule, ValidationError},
    ///     time::TimeRange,
    /// };
    ///
    /// let available_slots: Vec<TimeRange<u8>> = vec![TimeRange::new(0, 5)];
    ///
    /// // Only TimeRange(4, 5) are available for 3 of the meetings.
    /// let blocked_times: Vec<TimeRange<u8>> = vec![TimeRange::new(0, 3)];
    ///
    /// let mut meetings = Vec::with_capacity(5);
    /// for i in 0..3_u8 {
    ///     let participant = Participant::new(&i.to_string(), blocked_times.clone());
    ///
    ///     meetings.push(Meeting::new(&i.to_string(), vec![participant], 1));
    /// }
    ///
    /// // to avoid a PigonholeError, we create an extra meeting
    /// let participant = Participant::new("extra", vec![]);
    /// meetings.push(Meeting::new("extra", vec![participant], 1));
    ///
    /// // Trying to schedule this will trigger a NoSolution error no matter how many
    /// // iterations we provide it:
    /// let schedule = Schedule::new(meetings, available_slots);
    ///
    /// // First - A single iteration is attempted
    /// assert!(matches!(
    ///     schedule.schedule_meetings(Some(1)),
    ///     Err(ValidationError::NoSolution)
    /// ));
    ///
    /// // No matter how many iterations we provide, no solution will be found
    /// assert!(matches!(
    ///     schedule.schedule_meetings(None),
    ///     Err(ValidationError::NoSolution)
    /// ));
    /// ```
    pub fn schedule_meetings(
        &self,
        count: Option<usize>,
    ) -> Result<HashMap<String, TimeRange<N>>, ValidationError<N>> {
        let meetings = self
            .setup()?
            .into_iter()
            .map(|(id, duration, availability)| {
                (
                    id,
                    duration,
                    availability.iter().windowed(duration).collect::<Vec<_>>(),
                )
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
