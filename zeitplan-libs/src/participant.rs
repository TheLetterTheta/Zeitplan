use crate::time::{Available, Blocks, TimeRange};
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

#[cfg(feature = "arbitrary")]
impl<'a, N> arbitrary::Arbitrary<'a> for Participant<N>
where
    N: Integer + Copy + arbitrary::Arbitrary<'a> + Display + Debug,
{
    fn arbitrary(u: &mut arbitrary::Unstructured<'a>) -> arbitrary::Result<Self> {
        let blocked_times = u.arbitrary::<Vec<TimeRange<N>>>()?;
        let id = format!("{}", u.arbitrary::<uuid::Uuid>()?);
        Ok(Participant::new(&id, blocked_times))
    }
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
            available_times
                .iter()
                .blocks(self.blocked_times.iter())
                .collect()
        }
    }
}
