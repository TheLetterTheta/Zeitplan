use crate::meeting::Meeting;
use crate::time::{Available, Pigeons, TimeMerge, TimeRange, Validate, Windowed};
use core::fmt::{Debug, Display};
use itertools::Itertools;
use log::{debug, info, trace};
use num::traits::AsPrimitive;
use num::{CheckedAdd, CheckedSub, Integer, One};
use std::cmp::Ordering;
use std::collections::BTreeMap;
use std::ops::ControlFlow;
use thiserror::Error;

#[cfg(feature = "rayon")]
use rand::seq::SliceRandom;
#[cfg(feature = "rayon")]
use rayon::prelude::*;

#[cfg_attr(feature = "serde", derive(serde::Serialize))]
#[derive(Error, Debug, Eq, PartialEq)]
pub enum ValidationError<N>
where
    N: Integer + Debug + Display + Debug,
{
    #[error("Trying to schedule {pigeons} meetings in {pigeon_holes} available slots")]
    PigeonholeError { pigeons: N, pigeon_holes: N },
    #[error("No solution exists")]
    NoSolution,
    #[error("Could not find a solution within {0} iterations")]
    NoSolutionWithinIteration(usize),
    #[error("Bad Request\n{error}")]
    InvalidData { error: String },
    #[cfg(feature = "rayon")]
    #[error("Thread Interrupted")]
    Interrupted,
}

#[cfg(feature = "rayon")]
struct ScheduleShuffleIterator<N>
where
    N: Integer + Debug + Display + Debug + Copy,
{
    meetings: MeetingSchedule<N>,
    count: Option<usize>,
    flip: bool,
}

#[cfg(feature = "rayon")]
impl<N> Iterator for ScheduleShuffleIterator<N>
where
    N: Integer + Debug + Display + Debug + Copy,
{
    type Item = (bool, Option<usize>, MeetingSchedule<N>);

    fn next(&mut self) -> Option<Self::Item> {
        let rep = (false, self.count, self.meetings.clone());

        if self.flip {
            self.meetings.reverse();
        } else {
            let mut rng = rand::thread_rng();
            self.meetings.shuffle(&mut rng);
        }
        self.flip = !self.flip;

        Some(rep)
    }
}

#[cfg(feature = "rayon")]
fn schedule_shuffle<N>(
    count: Option<usize>,
    meetings: MeetingSchedule<N>,
) -> ScheduleShuffleIterator<N>
where
    N: Integer + Debug + Display + Debug + Copy,
{
    ScheduleShuffleIterator {
        meetings,
        count,
        flip: false,
    }
}

#[cfg_attr(feature = "serde", derive(serde::Deserialize))]
#[derive(Debug)]
pub struct Schedule<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    pub meetings: Vec<Meeting<N>>,
    pub availability: Vec<TimeRange<N>>,
}

#[derive(Debug, Clone)]
#[cfg_attr(feature = "serde", derive(serde::Serialize))]
pub struct ScheduleResult<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    pub count: usize,
    pub results: Vec<MeetingTime<N>>,
    pub indices: Vec<usize>,
}

#[derive(Debug, Clone)]
#[cfg_attr(feature = "serde", derive(serde::Serialize))]
pub struct MeetingTime<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    pub id: String,
    pub time: TimeRange<N>,
}

impl<N> Validate for Schedule<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    fn validate(&self) -> Result<(), String> {
        if let Some(a) = self
            .availability
            .iter()
            .map(|t| t.validate())
            .find(Result::is_err)
        {
            Err(format!(
                "Schedule contains invalid TimeRange:\n\t{}",
                a.unwrap_err()
            ))
        } else if let Some(m) = self
            .meetings
            .iter()
            .map(|m| m.validate())
            .find(Result::is_err)
        {
            Err(format!(
                "Schedule contains invalid meeting:\n\t{}",
                m.unwrap_err()
            ))
        } else {
            Ok(())
        }
    }
}

#[cfg(feature = "arbitrary")]
impl<
        'a,
        #[cfg(all(not(feature = "rayon"), feature = "serde"))] N: Display
            + Debug
            + Integer
            + One
            + Clone
            + AsPrimitive<usize>
            + Copy
            + std::iter::Sum
            + std::ops::AddAssign
            + CheckedSub
            + CheckedAdd
            + serde::Serialize
            + arbitrary::Arbitrary<'a>,
        #[cfg(all(not(feature = "rayon"), not(feature = "serde")))] N: Display
            + Debug
            + Integer
            + AsPrimitive<usize>
            + One
            + Clone
            + Copy
            + std::iter::Sum
            + std::ops::AddAssign
            + CheckedSub
            + CheckedAdd
            + arbitrary::Arbitrary<'a>,
        #[cfg(all(feature = "rayon", feature = "serde"))] N: Display
            + Debug
            + Integer
            + One
            + AsPrimitive<usize>
            + Clone
            + Copy
            + std::iter::Sum
            + std::ops::AddAssign
            + CheckedSub
            + CheckedAdd
            + std::marker::Send
            + std::marker::Sync
            + serde::Serialize
            + arbitrary::Arbitrary<'a>,
        #[cfg(all(feature = "rayon", not(feature = "serde")))] N: Display
            + Debug
            + Integer
            + One
            + Clone
            + Copy
            + AsPrimitive<usize>
            + std::iter::Sum
            + std::ops::AddAssign
            + CheckedSub
            + CheckedAdd
            + std::marker::Send
            + std::marker::Sync
            + arbitrary::Arbitrary<'a>,
    > arbitrary::Arbitrary<'a> for Schedule<N>
{
    fn arbitrary(u: &mut arbitrary::Unstructured<'a>) -> arbitrary::Result<Self> {
        let len = u.arbitrary_len::<usize>()?.max(1);
        let mut meetings = Vec::with_capacity(len);
        for _ in 0..len {
            meetings.push(u.arbitrary::<Meeting<N>>()?);
        }

        let mut availability = u.arbitrary::<Vec<TimeRange<N>>>()?;
        if availability.is_empty() {
            availability.push(u.arbitrary::<TimeRange<N>>()?);
        }
        Ok(Schedule::new(meetings, availability))
    }
}

#[derive(Debug, Clone, Eq, PartialEq)]
#[cfg_attr(feature = "serde", derive(serde::Serialize))]
pub struct MeetingScheduleInfo<N>
where
    N: Integer + Debug + Display + Debug + Copy,
{
    id: String,
    duration: N,
    availability: Vec<TimeRange<N>>,
}

pub enum SetOrder {
    Intersecting,
    SubsetL,
    SubsetR,
    NoIntersection,
}

impl<N> MeetingScheduleInfo<N>
where
    N: Integer + Debug + Display + Debug + Copy + std::iter::Sum,
{
    pub fn size(&self) -> N {
        self.availability
            .iter()
            .map(|time| (time.end - time.start) + <N>::one())
            .sum()
    }

    pub fn set_cmp(&self, other: &Self) -> SetOrder {
        let mut is_left_subset = true;
        let mut is_right_subset = true;
        let mut intersecting = false;

        let mut left_start = true;
        let mut right_start = true;

        let mut left_iterator = self
            .availability
            .iter()
            .flat_map(|time| [time.start, time.end]);
        let mut right_iterator = other
            .availability
            .iter()
            .flat_map(|time| [time.start, time.end]);

        if let Some(left) = left_iterator.next() {
        } else {
            if !right_start || right_iterator.next().is_some() {
                return if is_left_subset {
                    SetOrder::SubsetL
                } else if intersecting {
                    SetOrder::Intersecting
                } else {
                    SetOrder::NoIntersection
                };
            }
        }
        todo!()
    }
}

type MeetingSchedule<N> = Vec<MeetingScheduleInfo<N>>;

impl<
        #[cfg(all(not(feature = "rayon"), feature = "serde"))] N: Display
            + Debug
            + Integer
            + One
            + Clone
            + Copy
            + AsPrimitive<usize>
            + std::iter::Sum
            + std::ops::AddAssign
            + CheckedSub
            + CheckedAdd
            + serde::Serialize,
        #[cfg(all(not(feature = "rayon"), not(feature = "serde")))] N: Display
            + Debug
            + Integer
            + One
            + Clone
            + AsPrimitive<usize>
            + Copy
            + std::iter::Sum
            + std::ops::AddAssign
            + CheckedSub
            + CheckedAdd,
        #[cfg(all(feature = "rayon", feature = "serde"))] N: Display
            + Debug
            + Integer
            + One
            + Clone
            + Copy
            + AsPrimitive<usize>
            + std::iter::Sum
            + std::ops::AddAssign
            + CheckedSub
            + CheckedAdd
            + std::marker::Send
            + std::marker::Sync
            + serde::Serialize,
        #[cfg(all(feature = "rayon", not(feature = "serde")))] N: Display
            + Debug
            + Integer
            + One
            + AsPrimitive<usize>
            + Clone
            + Copy
            + std::iter::Sum
            + std::ops::AddAssign
            + CheckedSub
            + CheckedAdd
            + std::marker::Sync
            + std::marker::Send,
    > Schedule<N>
{
    /// Constucts a new Schedule to be scheduled
    pub fn new(meetings: Vec<Meeting<N>>, availability: Vec<TimeRange<N>>) -> Schedule<N> {
        Schedule {
            meetings,
            availability,
        }
    }

    fn meeting_availability(&self) -> MeetingSchedule<N> {
        self.meetings
            .iter()
            .filter_map(|meeting| {
                let meeting_availability = meeting.get_availability(&self.availability);
                // Skip meetings with no availability
                if meeting_availability.is_empty() {
                    None
                } else {
                    Some(MeetingScheduleInfo {
                        id: meeting.id.clone(),
                        duration: meeting.duration,
                        availability: meeting.get_availability(&self.availability),
                    })
                }
            })
            .sorted_unstable_by_key(|meeting| meeting.size())
            .collect()
    }

    pub fn compute_windows(&self) -> usize {
        self.meetings
            .iter()
            .map(|meeting| {
                let meeting_availability = meeting.get_availability(&self.availability);
                if meeting_availability.is_empty() {
                    <N>::one()
                } else {
                    meeting_availability
                        .iter()
                        .map(|t| t.end - t.start - (meeting.duration - <N>::one()))
                        .sum::<N>()
                }
            })
            .map(|n| n.as_())
            .product()
    }

    pub fn pigeon_check(schedule: &MeetingSchedule<N>) -> Option<ValidationError<N>> {
        let schedule = {
            let mut ret = Vec::with_capacity(schedule.len());

            let mut curr = None;
            for next in schedule.into_iter() {
                match curr {
                    None => {
                        curr = Some(next);
                    }
                    Some(mut prev) => {
                        if next.availability == prev.availability {
                            prev.duration = prev.duration + prev.duration;
                        } else {
                            ret.push(prev);
                            curr = Some(next);
                        }
                    }
                }
            }
            if let Some(prev) = curr {
                ret.push(prev);
            }

            ret
        };

        let mut subset_edges = vec![Vec::with_capacity(schedule.len()); schedule.len()];
        let mut intersection_edges = vec![Vec::with_capacity(schedule.len()); schedule.len()];

        schedule.iter().enumerate().tuple_combinations().for_each(
            |((l_index, left), (r_index, right))| match left.set_cmp(right) {
                SetOrder::Intersecting => {
                    intersection_edges[l_index].push(r_index);
                    intersection_edges[r_index].push(l_index);
                }
                SetOrder::SubsetL => {
                    subset_edges[r_index].push(l_index);
                }
                SetOrder::SubsetR => {
                    subset_edges[l_index].push(r_index);
                }
                SetOrder::NoIntersection => {}
            },
        );

        todo!()
    }

    pub fn setup(&self) -> Result<MeetingSchedule<N>, ValidationError<N>> {
        if let Err(e) = self.validate() {
            return Err(ValidationError::InvalidData { error: e });
        }

        let meeting_availability = self.meeting_availability();

        if let Some(error) = Self::pigeon_check(&meeting_availability) {
            return Err(error);
        }

        Ok(meeting_availability)
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
    ///     // This meeting's duration is 1
    ///     meetings.push(Meeting::new(&i.to_string(), vec![], 1));
    /// }
    ///
    /// let schedule = Schedule::new(meetings, available_slots);
    ///
    /// match schedule.schedule_meetings(None, None, None) {
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
    ///
    ///     // This meeting's duration is 1
    ///     meetings.push(Meeting::new(&i.to_string(), vec![TimeRange::new(150, 150)], 1));
    /// }
    ///
    /// let schedule = Schedule::new(meetings, available_slots);
    ///
    /// match schedule.schedule_meetings(None, None, None) {
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
    ///     meetings.push(Meeting::new(&i.to_string(), blocked_times.clone(), 1));
    /// }
    ///
    /// // to avoid a PigonholeError, we create an extra meeting
    /// meetings.push(Meeting::new("extra", vec![], 1));
    ///
    /// // Trying to schedule this will trigger a NoSolution error no matter how many
    /// // iterations we provide it:
    /// let schedule = Schedule::new(meetings, available_slots);
    ///
    /// // First - A single iteration is attempted
    /// assert!(matches!(
    ///     schedule.schedule_meetings(Some(1), None, None),
    ///     Err(ValidationError::NoSolutionWithinIteration(1))
    /// ));
    ///
    /// // No matter how many iterations we provide, no solution will be found
    /// assert!(matches!(
    ///     schedule.schedule_meetings(None, None, None),
    ///     Err(ValidationError::NoSolution)
    /// ));
    /// ```
    pub fn schedule_meetings(
        &self,
        count: Option<usize>,
        _per_thread: Option<usize>,
        _num_shuffles: Option<usize>,
    ) -> Result<ScheduleResult<N>, ValidationError<N>> {
        /*
        TODO: We do it like this for now because we can *technically* setup
        any iteration order we want. For instance - we can now spawn separate/
        threads such as: Default Order, Default Order Reversed, Random Order,
        Random Order Reversed, Sort Order, Sort Order Reversed, etc.
        */
        let meetings = {
            let mut setup = self.setup()?;
            #[cfg(feature = "rayon")]
            setup.par_sort_unstable_by(|a, b| {
                match (a
                    .availability
                    .iter()
                    .map(|t| t.end - t.start - (a.duration - <N>::one()))
                    .sum::<N>())
                .cmp(
                    &b.availability
                        .iter()
                        .map(|t| t.end - t.start - (b.duration - <N>::one()))
                        .sum::<N>(),
                ) {
                    Ordering::Equal => a.duration.cmp(&b.duration),
                    e => e,
                }
            });
            #[cfg(not(feature = "rayon"))]
            setup.sort_unstable_by(|a, b| {
                match (a
                    .availability
                    .iter()
                    .map(|t| t.end - t.start - (a.duration - <N>::one()))
                    .sum::<N>())
                .cmp(
                    &b.availability
                        .iter()
                        .map(|t| t.end - t.start - (b.duration - <N>::one()))
                        .sum::<N>(),
                ) {
                    Ordering::Equal => a.duration.cmp(&b.duration),
                    e => e,
                }
            });

            setup
        };

        #[cfg(feature = "serde")]
        debug!(target: "Schedule", meeting_config = log::as_serde!(meetings); "Searching solution in this configuration");
        #[cfg(not(feature = "serde"))]
        debug!(target: "Schedule", meeting_config = log::as_debug!(meetings); "Searching solution in this configuration");

        #[cfg(not(feature = "rayon"))]
        {
            Schedule::schedule_setup(self.meetings.len(), &meetings, count)
        }
        #[cfg(feature = "rayon")]
        {
            let should_stop = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));

            std::iter::once((true, count, meetings.clone()))
                .chain(
                    // If we assume 10K iterations per second,
                    // and a desired max search of 15 seconds on
                    // 3 (4 - 1 primary) threads in total: 45 total
                    // (worker) threads
                    // * This should probably be changed in the future
                    // * to be configurable
                    schedule_shuffle(
                    match (count, _per_thread) {
                        (Some(n), Some(o)) => Some(n.min(o)),
                        (Some(n), None) => Some(n),
                        (None, Some(o)) => Some(o),
                        (None, None) => None
                    },
                    meetings,
                ).take(_num_shuffles.unwrap_or(45)))
                .par_bridge()
                .find_map_any(
                    move |(is_primary, iteration_count, meeting_configuration)| {
                        #[cfg(feature = "serde")]
                        debug!(target: "Schedule", meeting_config = log::as_serde!(meeting_configuration); "Searching solution in this configuration");
                        #[cfg(not(feature = "serde"))]
                        debug!(target: "Schedule", meeting_config = log::as_debug!(meeting_configuration); "Searching solution in this configuration");
                        match Schedule::schedule_setup(
                            self.meetings.len(),
                            &meeting_configuration,
                            iteration_count,
                            should_stop.clone(),
                        ) {
                            r if is_primary => {
                                if matches!(r, Err(ValidationError::Interrupted)) {
                                    // Main thread finished, but was caused by another
                                    // thread locating the correct solution
                                    return None;
                                }
                                debug!(target: "Schedule", thread = "primary"; "Primary thread finished with result");
                                Some(r)
                            },
                            Ok(s) => {
                                debug!(target: "Schedule", thread = "worker"; "Worker thread found solution");
                                Some(Ok(s))
                            },
                            Err(ValidationError::NoSolution) => {
                                debug!(target: "Schedule", thread = "worker"; "Worker thread identified a no solution result");
                                Some(Err(ValidationError::NoSolution))
                            }
                            _ => {
                                trace!(target: "Schedule", thread = "worker"; "Worker thread exited");
                                None
                            },
                        }
                    },
                )
                .unwrap()
        }
    }

    fn schedule_setup(
        len: usize,
        meetings: &[MeetingScheduleInfo<N>],
        count: Option<usize>,
        #[cfg(feature = "rayon")] should_stop: std::sync::Arc<std::sync::atomic::AtomicBool>,
    ) -> Result<ScheduleResult<N>, ValidationError<N>> {
        let mut nth: usize = 1;
        let mut count_iter: usize = 0;
        let mut state: Vec<usize> = vec![0; len];
        let mut solution: BTreeMap<InternalTimeRange<N>, String> = BTreeMap::new();
        let mut last_key: Vec<TimeRange<N>> = Vec::with_capacity(len);

        loop {
            #[cfg(feature = "rayon")]
            if should_stop.load(std::sync::atomic::Ordering::SeqCst) {
                return Err(ValidationError::Interrupted);
            }

            if let Some(limit) = count {
                if limit == count_iter {
                    return Err(ValidationError::NoSolutionWithinIteration(limit));
                }
            }

            count_iter += 1;

            if meetings.iter().enumerate().skip(nth - 1).all(
                |(index, schedule_info)| match schedule_info.availability
                    .iter()
                    .windowed(schedule_info.duration)
                    .enumerate()
                    .skip(state[index])
                    .find(|(_time_index, time)| {
                        !solution.contains_key::<InternalTimeRange<N>>(&time.into())
                    }) {
                    Some((i, time)) => {

                        #[cfg(feature = "serde")]
                        trace!(target: "Schedule", time = log::as_serde!(time); "Attempting to add new time for scheduling");
                        #[cfg(not(feature = "serde"))]
                        trace!(target: "Schedule", time = log::as_display!(time); "Attempting to add new time for scheduling");

                        state[index] = i;
                        solution.insert(time.into(), schedule_info.id.to_owned());
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
                            #[cfg(feature = "serde")]
                            trace!(target: "Schedule", time = log::as_serde!(last); "Removing time from schedule and backtracing");
                            #[cfg(not(feature = "serde"))]
                            trace!(target: "Schedule", time = log::as_display!(last); "Removing time from schedule and backtracing");

                            solution.remove::<InternalTimeRange<N>>(&last.into());
                        }

                        nth -= 1;

                        false
                    }
                },
            ) {
                #[cfg(feature = "rayon")]
                let as_ret = solution
                    .into_par_iter()
                    .map(|(k, v)| MeetingTime { id: v, time: TimeRange::from(k)} )
                    .collect();
                #[cfg(not(feature = "rayon"))]
                let as_ret = solution
                    .into_iter()
                    .map(|(k, v)| MeetingTime { id: v, time: TimeRange::from(k)} )
                    .collect();

                #[cfg(feature = "serde")]
                {
                    info!(target: "Schedule", schedule = log::as_serde!(as_ret); "Solution found");
                    debug!(target: "Schedule", state = log::as_serde!(state); "Indices used for solution");
                }
                #[cfg(not(feature = "serde"))]
                {
                    info!(target: "Schedule", schedule = log::as_debug!(as_ret); "Solution found");
                    debug!(target: "Schedule", state = log::as_debug!(state); "Indices used for solution");
                }

                #[cfg(feature = "rayon")]
                // Stop processing on other threads
                should_stop.store(true, std::sync::atomic::Ordering::SeqCst);

                return Ok(ScheduleResult { count: count_iter, results: as_ret, indices: state });
            }
            if nth == 0 {
                #[cfg(feature = "rayon")]
                // Stop processing on other threads
                should_stop.store(true, std::sync::atomic::Ordering::SeqCst);

                return Err(ValidationError::NoSolution);
            }
        }
    }
}

/// Inclusive [start, end] time range
/// <N>: Any integer type
#[derive(Debug, Copy, Clone, Eq)]
struct InternalTimeRange<N>
where
    N: Integer + One + Copy,
{
    start: N,
    end: N,
}

impl<N> From<InternalTimeRange<N>> for TimeRange<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    fn from(other: InternalTimeRange<N>) -> Self {
        TimeRange::new(other.start, other.end)
    }
}

impl<N> From<TimeRange<N>> for InternalTimeRange<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    fn from(other: TimeRange<N>) -> Self {
        InternalTimeRange::new(other.start, other.end)
    }
}

impl<N> From<&TimeRange<N>> for InternalTimeRange<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    fn from(other: &TimeRange<N>) -> Self {
        InternalTimeRange::new(other.start, other.end)
    }
}

impl<N> InternalTimeRange<N>
where
    N: Integer + One + Copy,
{
    fn new(start: N, end: N) -> Self {
        if start > end {
            InternalTimeRange {
                start: end,
                end: start,
            }
        } else {
            InternalTimeRange { start, end }
        }
    }
}

impl<N> Ord for InternalTimeRange<N>
where
    N: Integer + Copy,
{
    fn cmp(&self, other: &Self) -> Ordering {
        match self.start.cmp(&other.start) {
            Ordering::Less if self.end < other.start => Ordering::Less,
            Ordering::Greater if self.start > other.end => Ordering::Greater,
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
        self.start == other.start && self.end == other.end
    }
}
