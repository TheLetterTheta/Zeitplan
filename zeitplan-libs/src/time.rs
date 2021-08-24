use core::cmp::Ordering;
use itertools::Itertools;
use num::{Integer, One};
use serde::{Deserialize, Serialize};

/// Inclusive [start, end] time range
/// <N>: Any integer type
#[derive(Deserialize, Serialize, Debug, Copy, Clone, Eq)]
pub struct TimeRange<N>(pub N, pub N)
where
    N: Integer + One + Copy;

impl<N> TimeRange<N>
where
    N: Integer + One + Copy,
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
        TimeRange(start, end)
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

impl<N> Ord for TimeRange<N>
where
    N: Integer + Copy,
{
    /// Custom comparison of TimeRange
    /// TimeRanges are equivalent if the times overlap
    /// TimeRanges are less IIF start and end are less
    /// TimeRanges are greater IIF start and end are greater
    ///
    /// # Examples
    /// ```
    /// use zeitplan_libs::time::TimeRange;
    ///
    /// let a = TimeRange::new(0, 0);
    /// let b = TimeRange::new(1, 1);
    ///
    /// assert!(a < b);
    ///
    /// let a = TimeRange::new(0, 1);
    /// assert_eq!(a, b);
    ///
    /// let a = TimeRange::new(0, 2);
    /// assert_eq!(a, b);
    ///
    /// let b = TimeRange::new(2, 2);
    /// assert_eq!(a, b);
    ///
    /// let a = TimeRange::new(2, 2);
    /// let b = TimeRange::new(1, 1);
    /// assert!(a > b);
    /// ```
    fn cmp(&self, other: &Self) -> Ordering {
        match self.start().cmp(&other.start()) {
            Ordering::Less if self.end() < other.start() => Ordering::Less,
            Ordering::Greater if self.start() > other.end() => Ordering::Greater,
            _ => Ordering::Equal,
        }
    }
}

impl<N> PartialOrd for TimeRange<N>
where
    N: Integer + Copy,
{
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl<N> PartialEq for TimeRange<N>
where
    N: Integer + Copy,
{
    fn eq(&self, other: &Self) -> bool {
        self.cmp(other) == Ordering::Equal
    }
}

pub trait Available<N>
where
    N: Integer + Copy,
{
    fn get_availability(self, available_times: &[TimeRange<N>]) -> Vec<TimeRange<N>>;
}

impl<'a, T, N> Available<N> for T
where
    T: Iterator<Item = &'a TimeRange<N>>,
    N: 'a + Integer + One + Copy,
{
    /// Self is blocked times that cannot be scheduled
    /// This performs a type of Set Exclusion of available times
    /// and self. `available_times - self`
    ///
    /// # Examples
    ///
    /// ```
    /// use zeitplan_libs::time::{Available, TimeRange};
    /// use zeitplan_libs::test_utils::{iter_test, TimeRangeTest};
    ///
    /// let blocked_times = vec![ TimeRange::new(1, 1) ];
    /// let available_times = vec![ TimeRange::new(0, 2) ];
    ///
    /// assert_eq!(
    ///     iter_test(&
    ///         blocked_times
    ///             .iter()
    ///             .get_availability(&available_times)),
    ///     vec![TimeRangeTest::new(0,0), TimeRangeTest::new(2, 2)]
    /// );
    /// ```
    fn get_availability(self, available_times: &[TimeRange<N>]) -> Vec<TimeRange<N>> {
        let blocked_iter = &mut self.sorted_unstable();

        let mut last_block: Option<&TimeRange<N>> = None;

        available_times
            .iter()
            .sorted_unstable()
            .flat_map(move |available_time| {
                let mut start: N;
                let end = available_time.1;
                let mut sub_times = vec![];

                start = match last_block {
                    Some(block) => available_time.start().max(block.end() + <N>::one()),
                    None => available_time.start(),
                };

                let mut blocking_times = blocked_iter
                    .skip_while(|block| block < &available_time)
                    .peekable();

                for block_time in
                    blocking_times.peeking_take_while(|block| *block == available_time)
                {
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

pub trait TimeMerge<N>
where
    N: Integer + Copy,
{
    fn time_merge(self) -> Vec<TimeRange<N>>;
}

impl<'a, T, N> TimeMerge<N> for T
where
    T: Iterator<Item = &'a TimeRange<N>>,
    N: 'a + Integer + One + Copy,
{
    /// Combines overlapping TimeRanges together
    ///
    /// # Examples
    /// ```
    /// use zeitplan_libs::time::{TimeMerge, TimeRange};
    /// use zeitplan_libs::test_utils::{iter_test, TimeRangeTest};
    ///
    /// let time_merge = vec![
    ///     TimeRange::new(0,0),
    ///     TimeRange::new(1,1),
    ///     TimeRange::new(0,1),
    ///     TimeRange::new(1, 3),
    ///     TimeRange::new(2, 4),
    ///     TimeRange::new(6,6)
    /// ];
    ///
    /// assert_eq!(
    ///     iter_test(&time_merge.iter().time_merge()),
    ///     vec![ TimeRangeTest::new(0, 4), TimeRangeTest::new(6,6) ]
    /// );
    /// ```
    fn time_merge(self) -> Vec<TimeRange<N>> {
        let size_hint = self.size_hint().1.unwrap_or(0);
        let (last, mut acc) = self.fold(
            (None, Vec::with_capacity(size_hint)),
            |(last, mut acc), &curr| match last {
                None => (Some(curr), acc),
                Some(time) => {
                    if TimeRange::new(time.start(), time.end() + <N>::one()) == curr {
                        (
                            Some(TimeRange::new(
                                time.start().min(curr.start()),
                                time.end().max(curr.end()),
                            )),
                            acc,
                        )
                    } else {
                        acc.push(time);
                        (Some(curr), acc)
                    }
                }
            },
        );

        if let Some(time) = last {
            acc.push(time);
        }

        acc
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
    N: 'a + Integer + One + Copy + std::iter::Sum,
{
    /// You cannot squeeze > N pigeons in <= N holes!
    /// We can "count" the pigeons of these `TimeRanges`
    ///
    /// # Examples
    /// ```
    /// use zeitplan_libs::time::{Pigeons, TimeRange};
    ///
    /// let times = vec![
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
    N: Integer + Copy,
{
    fn windowed(self, duration: N) -> Vec<TimeRange<N>>;
}

impl<'a, T, N> Windowed<N> for T
where
    T: Iterator<Item = &'a TimeRange<N>>,
    N: 'a + Integer + One + Copy,
{
    /// Splits a `TimeRange` into sections of windowed `TimeRange`s
    ///
    /// # Example
    /// ```
    /// use zeitplan_libs::time::{Windowed, TimeRange};
    /// use zeitplan_libs::test_utils::{iter_test, TimeRangeTest};
    ///
    /// let times = vec![ TimeRange::new(0, 4) ];
    ///
    /// assert_eq!(iter_test(&times.iter().windowed(1)),
    ///     vec![
    ///         TimeRangeTest::new(0,0),
    ///         TimeRangeTest::new(1,1),
    ///         TimeRangeTest::new(2,2),
    ///         TimeRangeTest::new(3,3),
    ///         TimeRangeTest::new(4,4),
    ///     ]
    /// );
    ///
    /// assert_eq!(iter_test(&times.iter().windowed(3)),
    ///     vec![
    ///         TimeRangeTest::new(0,2),
    ///         TimeRangeTest::new(1,3),
    ///         TimeRangeTest::new(2,4),
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
