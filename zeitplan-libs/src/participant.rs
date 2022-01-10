use crate::time::{Available, TimeRange};
use log::{debug, info, trace};
use num::{CheckedAdd, CheckedSub, Integer, One};
use serde::Deserialize;
use std::fmt::{Debug, Display};

#[derive(Clone, Deserialize, Debug)]
pub struct Participant<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    pub id: String,
    #[serde(rename = "blockedTimes")]
    pub blocked_times: Vec<TimeRange<N>>,
}

impl<N> Participant<N>
where
    N: Integer + One + Clone + Copy + Display + Debug,
{
    /// Constructs a new Participant with the specified block_times.
    /// This indicates times when this participant *cannot* meet.
    pub fn new(id: &str, blocked_times: Vec<TimeRange<N>>) -> Participant<N> {
        Participant {
            id: id.to_string(),
            blocked_times,
        }
    }
}

impl<N> Available<N> for Participant<N>
where
    N: Integer + One + Clone + Copy + CheckedAdd + CheckedSub + Display + Debug,
{
    /// Gets the availability for this participant within the provided
    /// `available_times`.
    fn get_availability(self, available_times: &[TimeRange<N>]) -> Vec<TimeRange<N>> {
        if available_times.is_empty() {
            vec![]
        } else if self.blocked_times.is_empty() {
            available_times.to_vec()
        } else {
            self.blocked_times.iter().get_availability(available_times)
        }
    }
}
