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

    pub fn start(self) -> N {
        self.0
    }

    pub fn end(self) -> N {
        self.1
    }
}

impl<N> Ord for TimeRange<N>
where
    N: Integer + Copy,
{
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
    fn time_merge(self) -> Vec<TimeRange<N>> {
        let size_hint = self.size_hint().1.unwrap_or(0);
        let (last, mut acc) = self.fold(
            (None, Vec::with_capacity(size_hint)),
            |(last, mut acc), &curr| match last {
                None => (Some(curr), acc),
                Some(time) => {
                    if TimeRange::new(time.start(), time.end() + <N>::one()) == curr {
                        (
                            Some(TimeRange::new(time.start().min(curr.start()), time.end().max(curr.end()))),
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
        self.map(|time| <N>::one() + (time.end() - time.start())).sum()
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
