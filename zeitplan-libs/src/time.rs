use core::cmp::Ordering;
use itertools::Itertools;
use log::{debug, trace};
use num::{CheckedAdd, CheckedSub, Integer, One, Zero};
use std::fmt::{Debug, Display};
use std::hash::Hash;

/// Inclusive [start, end] time range
/// <N>: Any integer type
#[derive(PartialEq, Hash, Debug, Copy, Clone, Eq)]
#[cfg_attr(feature = "serde", derive(serde::Deserialize, serde::Serialize))]
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

pub trait Validate {
    fn validate(&self) -> Result<(), String>;
}

impl<N> Validate for TimeRange<N>
where
    N: Integer + One + Copy + Display + Debug,
{
    fn validate(&self) -> Result<(), String> {
        if self.end() < self.start() {
            Err(format!(
                "Start ({}) is after End ({})",
                self.start(),
                self.end()
            ))
        } else {
            Ok(())
        }
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

#[derive(Eq, PartialEq, Debug)]
pub enum Time<N> {
    Start(N),
    End(N),
}

impl<N> Ord for Time<N>
where
    N: Ord,
{
    fn cmp(&self, other: &Self) -> Ordering {
        match self {
            Time::Start(v) => match other {
                Time::Start(o) => v.cmp(o),
                Time::End(o) => match v.cmp(o) {
                    Ordering::Equal => Ordering::Less,
                    Ordering::Less => Ordering::Less,
                    Ordering::Greater => Ordering::Greater,
                },
            },
            Time::End(v) => match other {
                Time::End(o) => v.cmp(o),
                Time::Start(o) => match v.cmp(o) {
                    Ordering::Equal => Ordering::Greater,
                    Ordering::Less => Ordering::Less,
                    Ordering::Greater => Ordering::Greater,
                },
            },
        }
    }
}

impl<N> PartialOrd for Time<N>
where
    N: Ord,
{
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

/// ```
/// use zeitplan_libs::time::{Blocks, TimeRange};
///
/// let available_times : Vec<TimeRange<u8>> = vec![ TimeRange::new(0, 2) ];
/// let blocked_times : Vec<TimeRange<u8>> = vec![ TimeRange::new(1, 1) ];
/// let block_result : Vec<TimeRange<u8>> =
///     vec![
///         TimeRange::new(0,0),
///         TimeRange::new(2,2)
///     ];
///
/// assert_eq!(
///     available_times
///         .iter()
///         .blocks(blocked_times.iter())
///         .collect::<Vec<TimeRange<u8>>>(),
///     block_result
/// );
///
/// let available_times : Vec<TimeRange<u8>> = vec![ TimeRange::new(0, 100), TimeRange::new(150, 150),
///                             TimeRange::new(200, 201) ];
/// let blocked_times : Vec<TimeRange<u8>> = vec![ TimeRange::new(150, 150) ];
/// let block_result : Vec<TimeRange<u8>> = vec![TimeRange::new(0,100), TimeRange::new(200, 201)];
///
/// assert_eq!(
///     available_times
///         .iter()
///         .blocks(blocked_times.iter())
///         .collect::<Vec<TimeRange<u8>>>(),
///    block_result
/// );
/// ```
#[derive(Debug)]
pub struct Blocker<N>
where
    N: Integer + Copy + Display + Debug,
{
    times: std::vec::IntoIter<Time<N>>,
    count: isize,
}

impl<N> Iterator for Blocker<N>
where
    N: Integer + Copy + Display + Debug + CheckedSub,
{
    type Item = TimeRange<N>;

    fn next(&mut self) -> Option<Self::Item> {
        while self.count < 1 {
            match self.times.next()? {
                Time::Start(s) if self.count == 0 => {
                    match self.times.next()? {
                        Time::End(e) => {
                            return Some(TimeRange::new(s, e));
                        }
                        _ => {
                            unreachable!();
                        }
                    };
                }
                Time::End(_) => {
                    self.count -= 1;
                }
                Time::Start(_) => {
                    self.count += 1;
                }
            }
        }

        None
    }
}

pub trait Blocks<'a, T, N>
where
    T: Iterator<Item = &'a TimeRange<N>>,
    N: 'a + Integer + Copy + Display + Debug,
{
    fn blocks(&mut self, blocking: T) -> Blocker<N>;
}

impl<'a, I, T, N> Blocks<'a, I, N> for T
where
    T: Iterator<Item = &'a TimeRange<N>>,
    I: Iterator<Item = &'a TimeRange<N>>,
    N: 'a + Integer + Copy + Display + Debug + CheckedSub + CheckedAdd,
{
    fn blocks(&mut self, blocking: I) -> Blocker<N> {
        let mut count = 0;
        let chain = self
            .time_merge()
            .flat_map(|time| [Time::Start(time.0), Time::End(time.1)])
            .merge(blocking.time_merge().flat_map(|time| {
                let mut times: Vec<Time<N>> = Vec::with_capacity(2);

                match time.0.checked_sub(&<N>::one()) {
                    Some(n) => times.push(Time::End(n)),
                    None => {
                        count -= 1;
                    }
                }

                if let Some(n) = time.1.checked_add(&<N>::one()) {
                    times.push(Time::Start(n))
                }

                times
            }))
            .collect_vec();

        Blocker {
            times: chain.into_iter(),
            count,
        }
    }
}

pub trait Available<N>
where
    N: Integer + Copy + Display + Debug,
{
    fn get_availability(&self, available_times: &[TimeRange<N>]) -> Vec<TimeRange<N>>;
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
    /// Returns an Option<N> if the result fails to add
    /// one. In this case - it can be assumed that there are the
    /// max number of pigeons, and therefore all checks can
    /// succeed/fail on that condition
    fn count_pigeons(&mut self) -> Option<N>;
}

impl<T, N> Pigeons<N> for T
where
    T: Iterator<Item = TimeRange<N>>,
    N: Integer + One + Zero + Copy + std::iter::Sum + Display + Debug + CheckedAdd,
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
    /// assert_eq!(times.into_iter().count_pigeons(), Some(11));
    ///
    /// let times : Vec<TimeRange<u8>> = vec![ TimeRange::new(0,255) ];
    ///
    /// // This is assumed to be the max value, and beyond the value stored within u8
    /// // (there are 256 available slots, and the max value allowed is 255)
    /// assert_eq!(times.into_iter().count_pigeons(), None);
    ///
    /// ```
    fn count_pigeons(&mut self) -> Option<N> {
        let mut sum = <N>::zero();
        for t in self.map(|time| (time.end() - time.start()).checked_add(&<N>::one())) {
            sum = sum + t?;
        }
        Some(sum)
    }
}

pub trait Windowed<'a, T, N>
where
    T: Iterator<Item = &'a TimeRange<N>>,
    N: 'a + Integer + Copy + Display + Debug,
{
    fn windowed(self, duration: N) -> TimeWindow<'a, T, N>;
}

#[derive(Clone)]
pub struct TimeWindow<'a, T, N>
where
    T: Iterator<Item = &'a TimeRange<N>>,
    N: 'a + Integer + Copy + Display + Debug,
{
    collection: T,
    duration: N,
    time: Option<TimeRange<N>>,
    start: N,
}

impl<'a, T, N> Iterator for TimeWindow<'a, T, N>
where
    T: Iterator<Item = &'a TimeRange<N>>,
    N: 'a + Integer + One + Copy + Display + Debug + CheckedSub + CheckedAdd,
{
    type Item = TimeRange<N>;

    fn next(&mut self) -> Option<Self::Item> {
        let zero_duration = self.duration.checked_sub(&<N>::one())?;
        loop {
            match self.time {
                Some(time) => {
                    if self.start.checked_add(&zero_duration)? > time.end() {
                        self.time = None;
                        continue;
                    }

                    let curr_start = self.start;
                    self.start = self.start.checked_add(&<N>::one())?;

                    return Some(TimeRange::new(curr_start, curr_start + zero_duration));
                }
                None => match self.collection.next() {
                    Some(time) => {
                        self.time = Some(*time);

                        let curr_start = time.start();

                        if curr_start.checked_add(&zero_duration)? > time.end() {
                            self.time = None;
                            continue;
                        }

                        self.start = curr_start.checked_add(&<N>::one())?;

                        return Some(TimeRange::new(curr_start, curr_start + zero_duration));
                    }
                    None => {
                        return None;
                    }
                },
            }
        }
    }
}

impl<'a, T, N> Windowed<'a, T, N> for T
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
    /// assert_eq!(times.iter().windowed(1).collect::<Vec<_>>(),
    ///     vec![
    ///         TimeRange::new(0,0),
    ///         TimeRange::new(1,1),
    ///         TimeRange::new(2,2),
    ///         TimeRange::new(3,3),
    ///         TimeRange::new(4,4),
    ///     ]
    /// );
    ///
    /// assert_eq!(times.iter().windowed(3).collect::<Vec<_>>(),
    ///     vec![
    ///         TimeRange::new(0,2),
    ///         TimeRange::new(1,3),
    ///         TimeRange::new(2,4),
    ///     ]
    /// );
    /// ```
    fn windowed(self, duration: N) -> TimeWindow<'a, T, N> {
        TimeWindow {
            collection: self,
            duration,
            time: None,
            start: <N>::zero(),
        }
        /*
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
        */
    }
}
