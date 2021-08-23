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
    pub fn new<'a>(id: &'a str, participants: Vec<Participant<N>>, duration: N) -> Meeting<N> {
        Meeting {
            id: id.to_string(),
            participants,
            duration,
        }
    }
}

impl<N> Available<N> for Meeting<N>
where
    N: Integer + One + Clone + Copy,
{
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
