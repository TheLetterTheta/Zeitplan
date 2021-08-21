use core::cmp::Ordering;
use itertools::Itertools;
use num::{Integer, One};
use serde::{Deserialize, Serialize};

#[derive(Deserialize, Serialize, Debug, Copy, Clone, Eq)]
pub struct TimeRange<N>(pub N, pub N)
where
    N: Integer + One + Copy;

impl<N> TimeRange<N>
where
    N: Integer + One + Copy,
{
    pub fn new(start: N, end: N) -> TimeRange<N> {
        TimeRange(start, end)
    }
}

impl<N> Ord for TimeRange<N>
where
    N: Integer + Copy,
{
    fn cmp(&self, other: &Self) -> Ordering {
        match self.0.cmp(&other.0) {
            Ordering::Less if self.1 < other.0 => Ordering::Less,
            Ordering::Greater if self.0 > other.1 => Ordering::Greater,
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
    fn get_availability<'a, 'b>(self, available_times: &'b [TimeRange<N>]) -> Vec<TimeRange<N>>;
}

impl<'a, T, N> Available<N> for T
where
    T: Iterator<Item = &'a TimeRange<N>>,
    N: 'a + Integer + One + Copy,
{
    fn get_availability<'b>(self, available_times: &'b [TimeRange<N>]) -> Vec<TimeRange<N>> {
        let blocked_iter = &mut self.sorted_unstable();

        let mut last_block: Option<&TimeRange<N>> = None;

        available_times
            .into_iter()
            .sorted_unstable()
            .flat_map(move |available_time| {
                let mut start: N;
                let end = available_time.1;
                let mut sub_times = vec![];

                start = match last_block {
                    Some(block) => available_time.0.max(block.1 + <N>::one()),
                    None => available_time.0,
                };

                let mut blocking_times = blocked_iter
                    .skip_while(|block| block < &available_time)
                    .peekable();

                for block_time in
                    blocking_times.peeking_take_while(|block| *block == available_time)
                {
                    if block_time.0 > start {
                        sub_times.push(TimeRange(start, block_time.0 - <N>::one()));
                    }

                    start = block_time.1 + <N>::one();
                    last_block = Some(block_time);
                }

                if let Some(block) = last_block {
                    if block.1 < end {
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
    fn time_merge(self) -> Vec<TimeRange<N>> {
        let size_hint = self.size_hint().1.unwrap_or(0);
        let (last, mut acc) = self.fold(
            (None, Vec::with_capacity(size_hint)),
            |(last, mut acc), &curr| match last {
                None => (Some(curr), acc),
                Some(time) => {
                    if TimeRange::new(time.0, time.1 + <N>::one()) == curr {
                        (
                            Some(TimeRange::new(time.0.min(curr.0), time.1.max(curr.1))),
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
    fn count_pigeons(&mut self) -> N {
        self.map(|time| <N>::one() + (time.1 - time.0)).sum()
    }
}
