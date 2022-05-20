use crate::participant::Participant;
use crate::time::{Available, Blocks, TimeRange, Validate};
use log::debug;
use num::{CheckedAdd, CheckedSub, Integer, One};
use std::fmt::{Debug, Display};

#[cfg_attr(feature = "serde", derive(serde::Deserialize))]
#[derive(Clone, Debug)]
pub struct MeetingParticipants<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    pub id: String,
    pub participants: Vec<Participant<N>>,
    pub duration: N,
}

impl<N> MeetingParticipants<N>
where
    N: Integer + One + Clone + Copy + Display + Debug,
{
    pub fn new(id: &str, participants: Vec<Participant<N>>, duration: N) -> MeetingParticipants<N> {
        MeetingParticipants {
            id: id.to_string(),
            participants,
            duration,
        }
    }
}

impl<N> From<MeetingParticipants<N>> for Meeting<N>
where
    N: Integer + One + Copy + Display + Debug + CheckedAdd,
{
    fn from(meeting: MeetingParticipants<N>) -> Self {
        use crate::time::TimeMerge;
        Meeting::new(
            &meeting.id,
            meeting
                .participants
                .iter()
                .flat_map(|p| p.blocked_times.iter())
                .time_merge()
                .collect(),
            meeting.duration,
        )
    }
}

#[cfg_attr(feature = "serde", derive(serde::Deserialize))]
#[derive(Clone, Debug)]
pub struct Meeting<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    pub id: String,
    #[cfg_attr(feature = "serde", serde(rename = "blockedTimes"))]
    pub blocked_times: Vec<TimeRange<N>>,
    pub duration: N,
}

impl<N> Validate for Meeting<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    fn validate(&self) -> Result<(), String> {
        if self.duration < <N>::one() {
            debug!(target:"Meeting", "Invalid Meeting Found: {}", self.id);
            Err(format!(
                "Meeting {} has an invalid duration {}",
                self.id, self.duration
            ))
        } else if let Some(Err(p)) = self
            .blocked_times
            .iter()
            .map(|p| p.validate())
            .find(Result::is_err)
        {
            debug!(target:"Meeting", "Invalid Meeting Found: {}", self.id);
            Err(format!(
                "Meeting {} has an invalid participant value:\n\t {}",
                self.id, p
            ))
        } else {
            Ok(())
        }
    }
}

#[cfg(feature = "arbitrary")]
impl<'a, N> arbitrary::Arbitrary<'a> for Meeting<N>
where
    N: Integer + Copy + arbitrary::Arbitrary<'a> + Display + Debug,
{
    fn arbitrary(u: &mut arbitrary::Unstructured<'a>) -> arbitrary::Result<Self> {
        let times = u.arbitrary::<Vec<TimeRange<N>>>()?;

        let id = format!("{}", u.arbitrary::<uuid::Uuid>()?);

        let n = u.arbitrary::<N>()?.max(<N>::one());
        Ok(Meeting::new(&id, times, n))
    }
}

impl<N> Meeting<N>
where
    N: Integer + One + Clone + Copy + Display + Debug,
{
    pub fn new(id: &str, blocked_times: Vec<TimeRange<N>>, duration: N) -> Meeting<N> {
        Meeting {
            id: id.to_string(),
            blocked_times,
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
    N: Integer + One + Clone + Copy + CheckedAdd + CheckedSub + Display + Debug,
{
    /// Iterates each participant's `block_times`, sorts them,
    /// then performs a `TimeMerge` to consolodate the combined block_times.
    /// We then use this against the `available_times` to produce values for which
    /// this meeting can be scheduled
    ///
    /// # Examples
    /// ```
    /// use zeitplan_libs::meeting::{MeetingParticipants, Meeting};
    /// use zeitplan_libs::participant::Participant;
    /// use zeitplan_libs::time::{Available, TimeRange};
    ///
    /// let blocked_times_1 : Vec<TimeRange<u8>> = vec![
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
    /// let meeting = MeetingParticipants::new(&"1", participants, 1);
    /// let meeting: Meeting<u8> = meeting.into();
    ///
    /// let available_time = vec![
    ///     TimeRange::new(1, 4),
    /// ];
    ///
    /// assert_eq!(
    ///     meeting.get_availability(&available_time),
    ///     vec![TimeRange::new(2, 2)]
    /// );
    /// ```
    fn get_availability(&self, available_times: &[TimeRange<N>]) -> Vec<TimeRange<N>> {
        if available_times.is_empty() {
            return vec![];
        }

        available_times
            .iter()
            .blocks(self.blocked_times.iter())
            .filter(|&time| {
                (time.1 - time.0)
                    .checked_add(&<N>::one())
                    .map(|n| n >= self.duration)
                    // Only happens if timespan is the max value available
                    // - there would be no duration above this
                    .unwrap_or(true)
            })
            .collect()
    }
}
