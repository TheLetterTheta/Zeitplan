use core::cmp::Ordering;
use itertools::Itertools;
use log::{debug, info, trace};
use num::{CheckedAdd, CheckedSub, Integer, One};
use serde::{Deserialize, Serialize};
use std::fmt::{Debug, Display};

/// Inclusive [start, end] time range
/// <N>: Any integer type
#[derive(Deserialize, Serialize, Debug, Copy, Clone, Eq)]
pub struct TimeRange<N>(pub N, pub N)
where
    N: Integer + One + Copy + Display + Debug;

impl<N> TimeRange<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    /// Construct a new Time Range
    /// Range is inclusive on [start, end]
    /// # Examples
    /// ```
    /// use zeitplan_libs::time::TimeRange;
    ///
    /// let test = TimeRange::new(0, 100);
    ///
    /// assert_eq!(test.0, 0);
    /// assert_eq!(test.1, 100);
    /// ```
    pub fn new(start: N, end: N) -> TimeRange<N> {
        if end < start {
            debug!("TimeRange::new called with end before start");
            TimeRange(end, start)
        } else {
            TimeRange(start, end)
        }
    }

    /// Convenience function for readability
    /// Returns the start of the TimeRange
    ///
    /// # Examples
    /// ```
    /// use zeitplan_libs::time::TimeRange;
    ///
    /// let test = TimeRange::new(0, 100);
    /// assert_eq!(test.0, test.start());
    /// ```
    pub fn start(self) -> N {
        self.0
    }

    /// Convenience function for readability
    /// Returns the start of the TimeRange
    ///
    /// # Examples
    /// ```
    /// use zeitplan_libs::time::TimeRange;
    ///
    /// let test = TimeRange::new(0, 100);
    /// assert_eq!(test.1, test.end());
    /// ```
    pub fn end(self) -> N {
        self.1
    }
}

impl<N> Display for TimeRange<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> Result<(), std::fmt::Error> {
        write!(f, "TimeRange({}, {})", self.0, self.1)
    }
}

#[cfg(feature = "arbitrary")]
impl<'a, N> arbitrary::Arbitrary<'a> for TimeRange<N>
where
    N: Integer + Copy + arbitrary::Arbitrary<'a> + Display + Debug,
{
    fn arbitrary(u: &mut arbitrary::Unstructured<'a>) -> arbitrary::Result<Self> {
        let (a, b) = u.arbitrary::<(N, N)>()?;
        Ok(TimeRange::new(a, b))
    }
}

impl<N> PartialOrd for TimeRange<N>
where
    N: Integer + Copy + Display + Debug,
{
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        trace!(target: "TimeRange", "partial_cmp {} and {}", self, other);
        match self.start().cmp(&other.start()) {
            Ordering::Less if self.end() < other.start() => Some(Ordering::Less),
            Ordering::Greater if self.start() > other.end() => Some(Ordering::Greater),
            Ordering::Equal if self.end().eq(&other.end()) => Some(Ordering::Equal),
            _ => {
                debug!(target: "TimeRange", "Time Ranges must overlap, and are not able to be \"compared\"");
                None
            }
        }
    }
}

impl<N> PartialEq for TimeRange<N>
where
    N: Integer + Copy + Display + Debug,
{
    fn eq(&self, other: &Self) -> bool {
        self.0 == other.0 && self.1 == other.1
    }
}

pub trait Available<N>
where
    N: Integer + Copy + Display + Debug,
{
    fn get_availability(self, available_times: &[TimeRange<N>]) -> Vec<TimeRange<N>>;
}

impl<'a, T, N> Available<N> for T
where
    T: IntoIterator<Item = &'a TimeRange<N>>,
    N: 'a + Integer + One + Copy + CheckedAdd + CheckedSub + Display + Debug,
{
    /// Self is blocked times that cannot be scheduled
    /// This performs a type of Set Exclusion of available times
    /// and self. `available_times - self`
    ///
    /// # Examples
    ///
    /// ```
    /// use zeitplan_libs::time::{Available, TimeRange};
    ///
    /// let blocked_times : Vec<TimeRange<u8>> = vec![ TimeRange::new(1, 1) ];
    /// let available_times = vec![ TimeRange::new(0, 2) ];
    ///
    /// assert_eq!(
    ///     blocked_times
    ///         .iter()
    ///         .get_availability(&available_times),
    ///     vec![TimeRange::new(0,0), TimeRange::new(2, 2)]
    /// );
    /// ```
    fn get_availability(self, available_times: &[TimeRange<N>]) -> Vec<TimeRange<N>> {
        let blocked_iter = &mut self.into_iter().time_merge();

        let mut last_block: Option<TimeRange<N>> = None;

        available_times
            .iter()
            .time_merge()
            .flat_map(move |available_time| {
                let end = available_time.1;
                let mut sub_times = vec![];

                let mut start: N = match last_block {
                    Some(block) => available_time.start().max(block.end() + <N>::one()),
                    None => available_time.start(),
                };

                let mut blocking_times = blocked_iter
                    .skip_while(|block| block < &available_time)
                    .peekable();

                for block_time in blocking_times.peeking_take_while(|block| {
                    matches!(
                        block.partial_cmp(&available_time),
                        None | Some(Ordering::Equal)
                    )
                }) {
                    if block_time.start() > start {
                        sub_times.push(TimeRange(start, block_time.start() - <N>::one()));
                    }

                    start = block_time.end() + <N>::one();
                    last_block = Some(block_time);
                }

                if let Some(block) = last_block {
                    if block.end() < end {
                        sub_times.push(TimeRange(start, end));
                    }
                }

                if let Some(&block) = blocking_times.peek() {
                    last_block = Some(block);
                }

                sub_times
            })
            .collect_vec()
    }
}

#[derive(Debug, Clone)]
pub struct TimeMergeIterator<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    collection: std::iter::Peekable<std::vec::IntoIter<TimeType<N>>>,
}

impl<N> Iterator for TimeMergeIterator<N>
where
    N: Integer + One + Copy + Display + Debug + CheckedAdd,
{
    type Item = TimeRange<N>;

    fn next(&mut self) -> Option<Self::Item> {
        let start: TimeType<N> = self.collection.next()?;

        // We always continue at the next start
        debug_assert!(matches!(start, TimeType::Start(_)));

        let start = match start {
            TimeType::Start(n) => n,
            _ => unreachable!(),
        };
        let mut end: N = <N>::one();

        let mut count = 0;

        loop {
            count += 1;

            while count > 0 {
                match self.collection.next()? {
                    TimeType::Start(_) => count += 1,
                    TimeType::End(n) => {
                        end = n;
                        count -= 1;
                    }
                }
            }

            if let Some(checked_end) = end.checked_add(&<N>::one()) {
                match self.collection.peek() {
                    Some(TimeType::Start(v)) if *v <= checked_end => {
                        self.collection.next(); // Throw away new "start"
                    }
                    _ => break,
                }
            } else {
                break;
            }
        }

        Some(TimeRange::new(start, end))
    }
}

#[derive(Debug, Eq, PartialEq, Copy, Clone)]
enum TimeType<N> {
    Start(N),
    End(N),
}

impl<N> PartialOrd for TimeType<N>
where
    N: Ord,
{
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl<N> Ord for TimeType<N>
where
    N: Ord,
{
    fn cmp(&self, other: &Self) -> Ordering {
        let one = match self {
            TimeType::Start(v) => v,
            TimeType::End(v) => v,
        };
        let other_time = match other {
            TimeType::Start(v) => v,
            TimeType::End(v) => v,
        };

        match one.cmp(other_time) {
            Ordering::Less => Ordering::Less,
            Ordering::Greater => Ordering::Greater,
            Ordering::Equal => {
                if (matches!(self, TimeType::Start(_)) && matches!(other, TimeType::Start(_)))
                    || (matches!(self, TimeType::End(_)) && matches!(other, TimeType::End(_)))
                {
                    Ordering::Equal
                } else if matches!(self, TimeType::Start(_)) {
                    Ordering::Less
                } else {
                    Ordering::Greater
                }
            }
        }
    }
}

pub trait TimeMerge<N>
where
    N: Integer + Copy + Display + Debug,
{
    fn time_merge(self) -> TimeMergeIterator<N>;
}

impl<'a, T, N> TimeMerge<N> for T
where
    T: Iterator<Item = &'a TimeRange<N>>,
    N: 'a + Integer + One + Copy + Display + Debug,
{
    /// Combines overlapping TimeRanges together
    ///
    /// # Examples
    /// ```
    /// use zeitplan_libs::time::{TimeMerge, TimeRange};
    ///
    /// let time_merge : Vec<TimeRange<u8>>= vec![
    ///     TimeRange::new(0,0),
    ///     TimeRange::new(1,1),
    ///     TimeRange::new(0,1),
    ///     TimeRange::new(1, 3),
    ///     TimeRange::new(2, 4),
    ///     TimeRange::new(6,6)
    /// ];
    ///
    /// assert_eq!(
    ///     time_merge.iter().time_merge().collect::<Vec<_>>(),
    ///     vec![ TimeRange::new(0, 4), TimeRange::new(6,6) ]
    /// );
    /// ```
    fn time_merge(self) -> TimeMergeIterator<N> {
        TimeMergeIterator {
            collection: self
                .flat_map(|t| [TimeType::Start(t.start()), TimeType::End(t.end())])
                .sorted_unstable()
                .peekable(),
        }
    }
}

pub trait Pigeons<N>
where
    N: Integer,
{
    fn count_pigeons(&mut self) -> N;
}

impl<'a, T, N> Pigeons<N> for T
where
    T: Iterator<Item = &'a TimeRange<N>>,
    N: 'a + Integer + One + Copy + std::iter::Sum + Display + Debug,
{
    /// You cannot squeeze > N pigeons in <= N holes!
    /// We can "count" the pigeons of these `TimeRanges`
    ///
    /// # Examples
    /// ```
    /// use zeitplan_libs::time::{Pigeons, TimeRange};
    ///
    /// let times : Vec<TimeRange<u8>> = vec![
    ///     TimeRange::new(0,9),
    ///     TimeRange::new(11, 11)
    /// ];
    ///
    /// assert_eq!(times.iter().count_pigeons(), 11);
    ///
    /// ```
    fn count_pigeons(&mut self) -> N {
        self.map(|time| <N>::one() + (time.end() - time.start()))
            .sum()
    }
}

pub trait Windowed<N>
where
    N: Integer + Copy + Display + Debug,
{
    fn windowed(self, duration: N) -> Vec<TimeRange<N>>;
}

impl<'a, T, N> Windowed<N> for T
where
    T: Iterator<Item = &'a TimeRange<N>>,
    N: 'a + Integer + One + Copy + Display + Debug,
{
    /// Splits a `TimeRange` into sections of windowed `TimeRange`s
    ///
    /// # Example
    /// ```
    /// use zeitplan_libs::time::{Windowed, TimeRange};
    ///
    /// let times = vec![ TimeRange::new(0, 4) ];
    ///
    /// assert_eq!(times.iter().windowed(1),
    ///     vec![
    ///         TimeRange::new(0,0),
    ///         TimeRange::new(1,1),
    ///         TimeRange::new(2,2),
    ///         TimeRange::new(3,3),
    ///         TimeRange::new(4,4),
    ///     ]
    /// );
    ///
    /// assert_eq!(times.iter().windowed(3),
    ///     vec![
    ///         TimeRange::new(0,2),
    ///         TimeRange::new(1,3),
    ///         TimeRange::new(2,4),
    ///     ]
    /// );
    /// ```
    fn windowed(self, duration: N) -> Vec<TimeRange<N>> {
        let mut windows: Vec<TimeRange<N>> = Vec::with_capacity(self.size_hint().1.unwrap_or(0));

        let zero_duration = duration - <N>::one();

        for time in self {
            let mut start = time.start();

            while start + zero_duration <= time.end() {
                windows.push(TimeRange::new(start, start + zero_duration));
                start = start + <N>::one();
            }
        }

        windows
    }
}
