use crate::participant::Participant;
use crate::time::{Available, TimeMerge, TimeRange};
use itertools::Itertools;
use num::{Integer, One};
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone)]
pub struct Meeting<N>
where
    N: Integer + One + Copy,
{
    pub id: String,
    pub participants: Vec<Participant<N>>,
    pub duration: N,
}

impl<N> Meeting<N>
where
    N: Integer + One + Clone + Copy,
{
    pub fn new(id: &str, participants: Vec<Participant<N>>, duration: N) -> Meeting<N> {
        Meeting {
            id: id.to_string(),
            participants,
            duration,
        }
    }

    /// Meetings should be pre-sorted before attempting to schedule.
    /// This method produces a value for each meeting which represents
    /// the number of slots that this meeting can be scheduled within.
    ///
    /// We choose here to start with meetings with less overall availability
    /// to schedule _first_.
    pub fn sort_val(&self, available_times: &[TimeRange<N>]) -> N {
        available_times.iter().fold(<N>::one(), |acc, time| {
            acc + time.1 - (self.duration + time.0 + <N>::one())
        })
    }
}

impl<N> Available<N> for Meeting<N>
where
    N: Integer + One + Clone + Copy,
{
    /// Iterates each participant's `block_times`, sorts them,
    /// then performs a `TimeMerge` to consolodate the combined block_times.
    /// We then use this against the `available_times` to produce values for which
    /// this meeting can be scheduled
    ///
    /// # Examples
    /// ```
    /// use zeitplan_libs::meeting::Meeting;
    /// use zeitplan_libs::participant::Participant;
    /// use zeitplan_libs::time::{Available, TimeRange};
    /// use zeitplan_libs::test_utils::{iter_test, TimeRangeTest};
    ///
    /// let blocked_times_1 = vec![
    ///     TimeRange::new(1, 1),
    /// ];
    ///
    /// let blocked_times_2 = vec![
    ///     TimeRange::new(3, 3),
    ///     TimeRange::new(4, 4)
    /// ];
    ///
    /// let participants = vec![
    ///     Participant::new(&"1", blocked_times_1),
    ///     Participant::new(&"2", blocked_times_2),
    /// ];
    ///
    /// let meeting = Meeting::new(&"1", participants, 1);
    ///
    /// let available_time = vec![
    ///     TimeRange::new(1, 4),
    /// ];
    ///
    /// assert_eq!(
    ///     iter_test(&meeting.get_availability(&available_time)),
    ///     vec![TimeRangeTest::new(2, 2)]
    /// );
    /// ```
    fn get_availability(self, available_times: &[TimeRange<N>]) -> Vec<TimeRange<N>> {
        if available_times.is_empty() {
            return vec![];
        }

        let block_times = self
            .participants
            .iter()
            .flat_map(|p| p.blocked_times.iter())
            .sorted_unstable()
            .time_merge();

        if block_times.is_empty() {
            available_times.to_vec()
        } else {
            block_times
                .iter()
                .get_availability(available_times)
                .into_iter()
                .filter(|&time| <N>::one() + (time.1 - time.0) >= self.duration)
                .collect_vec()
        }
    }
}
