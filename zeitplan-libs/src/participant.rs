use crate::time::{Available, TimeRange};
use num::{Integer, One};
use serde::{Deserialize, Serialize};

#[derive(Clone, Serialize, Deserialize)]
pub struct Participant<'a, N>
where
    N: Integer + One + Copy,
{
    pub id: &'a str,
    pub blocked_times: Vec<TimeRange<N>>,
}

impl<'a, N> Participant<'a, N>
where
    N: Integer + One + Clone + Copy,
{
    pub fn new(id: &'a str, blocked_times: Vec<TimeRange<N>>) -> Participant<'a, N> {
        Participant { id, blocked_times }
    }
}

impl<N> Available<N> for Participant<'_, N>
where
    N: Integer + One + Clone + Copy,
{
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
