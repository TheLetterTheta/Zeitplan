use itertools::Itertools;
use std::collections::BTreeMap;

mod data;
mod input;

use crate::data::*;
use crate::input::ScheduleInput;

pub fn schedule_meetings(
    input: &ScheduleInput,
    count: Option<usize>,
) -> Result<BTreeMap<TimeRange, &str>, ValidationError> {
    let meetings = input
        .meetings
        .iter()
        .filter(|(_, meeting)| meeting.available_times.len() > 0)
        .map(|(k, m)| {
            (
                k,
                m.available_times
                    .iter()
                    .flat_map(move |t| {
                        let duration = m.duration - 1;
                        (t.0..=(t.1 - duration)).map(move |s| TimeRange(s, s + duration))
                    })
                    .collect::<Vec<_>>(),
            )
        })
        .sorted_unstable_by_key(|(_, a)| a.len())
        .collect::<Vec<_>>();

    let mut x: usize = 1;
    let mut iter: usize = 0;
    let mut state: Vec<usize> = vec![0; meetings.len()];
    let mut solution: BTreeMap<TimeRange, &str> = BTreeMap::new();
    let mut last_key: Vec<TimeRange> = Vec::with_capacity(meetings.len());

    loop {
        if let Some(limit) = count {
            if limit > iter {
                return Err(ValidationError::NoSolution);
            }
            iter += 1;
        }

        if meetings
            .iter()
            .enumerate()
            .skip(x - 1)
            .all(|(index, (meeting_id, meeting_times))| {
                match meeting_times
                    .iter()
                    .enumerate()
                    .skip(state[index])
                    .skip_while(|(_time_index, time)| solution.contains_key(*time))
                    .next()
                {
                    Some((i, time)) => {
                        state[index] = i;
                        solution.insert(*time, meeting_id);
                        last_key.push(*time);
                        x += 1;
                        true
                    }
                    None => {
                        state[index] = 0;
                        if index > 0 {
                            state[index - 1] += 1;
                        }
                        solution.remove(&last_key.pop().unwrap());
                        x -= 1;

                        false
                    }
                }
            })
        {
            return Ok(solution);
        }

        if x == 0 {
            return Err(ValidationError::NoSolution);
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::input::*;
    use crate::*;
    use std::collections::HashMap;

    #[test]
    fn validates_invalid_input() {
        let mut test_input = Input::new(
            HashMap::new(),
            HashMap::new(),
            (0..300).map(|n| TimeRange(n, n)).collect(),
        );

        assert!(match test_input.validate() {
            Err(ValidationError::UnsupportedLength {
                expected: _,
                found: _,
            }) => true,
            _ => false,
        });

        let mut test_input = Input::new(
            (0..200)
                .map(|n| (n.to_string(), Participant::default()))
                .collect(),
            HashMap::new(),
            vec![],
        );

        assert!(match test_input.validate() {
            Err(ValidationError::UnsupportedLength {
                expected: _,
                found: _,
            }) => true,
            _ => false,
        });
    }

    #[test]
    fn sort_input_works() {
        let mut test_input = Input::new(
            vec![(
                "0".to_string(),
                Participant::new(vec![
                    TimeRange(20, 22),
                    TimeRange(1, 3),
                    TimeRange(9, 12),
                    TimeRange(4, 8),
                ]),
            )]
            .into_iter()
            .collect(),
            HashMap::new(),
            vec![
                TimeRange(20, 22),
                TimeRange(1, 3),
                TimeRange(9, 12),
                TimeRange(4, 8),
            ],
        );

        assert!(test_input.sort().is_ok());

        assert_eq!(
            test_input.participants.get("0").unwrap().blocked_times,
            vec![
                TimeRange(1, 3),
                TimeRange(4, 8),
                TimeRange(9, 12),
                TimeRange(20, 22),
            ]
        );
        assert_eq!(
            test_input.available_times,
            vec![
                TimeRange(1, 3),
                TimeRange(4, 8),
                TimeRange(9, 12),
                TimeRange(20, 22),
            ]
        );
    }

    #[test]
    fn sort_input_validation() {
        let mut test_input = Input::new(
            vec![(
                "0".to_string(),
                Participant::new(vec![TimeRange(0, 1), TimeRange(1, 1)]),
            )]
            .into_iter()
            .collect(),
            HashMap::new(),
            vec![],
        );

        assert!(match test_input.sort() {
            Err(ValidationError::OverlappingTimeRange {
                location: _,
                value: _,
            }) => true,
            _ => false,
        });

        let mut test_input = Input::new(
            vec![(
                "0".to_string(),
                Participant::new(vec![TimeRange(0, 3), TimeRange(1, 5)]),
            )]
            .into_iter()
            .collect(),
            HashMap::new(),
            vec![],
        );

        assert!(match test_input.sort() {
            Err(ValidationError::OverlappingTimeRange {
                location: _,
                value: _,
            }) => true,
            _ => false,
        });

        let mut test_input = Input::new(
            HashMap::new(),
            HashMap::new(),
            vec![TimeRange(0, 1), TimeRange(1, 1)],
        );

        assert!(match test_input.sort() {
            Err(ValidationError::OverlappingTimeRange {
                location: _,
                value: _,
            }) => true,
            _ => false,
        });
        let mut test_input = Input::new(
            HashMap::new(),
            HashMap::new(),
            vec![TimeRange(0, 3), TimeRange(1, 5)],
        );

        assert!(match test_input.sort() {
            Err(ValidationError::OverlappingTimeRange {
                location: _,
                value: _,
            }) => true,
            _ => false,
        });
    }

    #[test]
    fn gets_user_availability() {
        let mut test_input = Input::new(
            vec![
                (
                    "0".to_string(),
                    Participant::new(vec![TimeRange(0, 0), TimeRange(2, 5), TimeRange(9, 9)]),
                ),
                (
                    "1".to_string(),
                    Participant::new(vec![TimeRange(1, 1), TimeRange(3, 3), TimeRange(7, 8)]),
                ),
                ("2".to_string(), Participant::new(vec![TimeRange(1, 8)])),
                ("3".to_string(), Participant::new(vec![])),
                ("4".to_string(), Participant::new(vec![TimeRange(2, 7)])),
                ("5".to_string(), Participant::new(vec![TimeRange(9, 9)])),
            ]
            .into_iter()
            .collect(),
            HashMap::new(),
            vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)],
        );

        assert!(test_input.sort().is_ok());
        let _ = test_input.get_user_availability();

        assert_eq!(
            test_input.participants.get("0").unwrap().available_times,
            vec![
                TimeRange(1, 1),
                TimeRange(6, 6),
                TimeRange(8, 8),
                TimeRange(10, 11)
            ]
        );

        assert_eq!(
            test_input.participants.get("1").unwrap().available_times,
            vec![TimeRange(0, 0), TimeRange(4, 6), TimeRange(9, 11),]
        );

        assert_eq!(
            test_input.participants.get("2").unwrap().available_times,
            vec![TimeRange(0, 0), TimeRange(9, 11),]
        );

        assert_eq!(
            test_input.participants.get("3").unwrap().available_times,
            vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)]
        );

        assert_eq!(
            test_input.participants.get("4").unwrap().available_times,
            vec![TimeRange(0, 1), TimeRange(8, 11)]
        );

        assert_eq!(
            test_input.participants.get("5").unwrap().available_times,
            vec![
                TimeRange(0, 1),
                TimeRange(3, 6),
                TimeRange(8, 8),
                TimeRange(10, 11)
            ]
        );
    }

    #[test]
    fn gets_meeting_availability() {
        let mut test_input = Input::new(
            vec![
                (
                    "0".to_string(),
                    Participant::new(vec![TimeRange(0, 0), TimeRange(2, 5), TimeRange(9, 9)]),
                ),
                (
                    "1".to_string(),
                    Participant::new(vec![TimeRange(1, 1), TimeRange(3, 3), TimeRange(7, 8)]),
                ),
                ("2".to_string(), Participant::new(vec![TimeRange(1, 8)])),
                ("3".to_string(), Participant::new(vec![])),
                ("4".to_string(), Participant::new(vec![TimeRange(0, 7)])),
                ("5".to_string(), Participant::new(vec![TimeRange(8, 12)])),
            ]
            .into_iter()
            .collect(),
            vec![
                (
                    "0".to_string(),
                    Meeting::new(1, vec!["0".to_string(), "1".to_string()]),
                ),
                (
                    "1".to_string(),
                    Meeting::new(2, vec!["0".to_string(), "1".to_string()]),
                ),
                (
                    "2".to_string(),
                    Meeting::new(1, vec!["1".to_string(), "2".to_string()]),
                ),
                (
                    "3".to_string(),
                    Meeting::new(1, vec!["0".to_string(), "1".to_string(), "2".to_string()]),
                ),
                (
                    "4".to_string(),
                    Meeting::new(1, vec!["4".to_string(), "5".to_string()]),
                ),
            ]
            .into_iter()
            .collect(),
            vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)],
        );

        assert!(test_input.sort().is_ok());
        let _ = test_input.get_user_availability();
        let _ = test_input.get_meeting_availability();

        assert_eq!(
            test_input.meetings.get("0").unwrap().available_times,
            vec![TimeRange(6, 6), TimeRange(10, 11)]
        );

        assert_eq!(
            test_input.meetings.get("1").unwrap().available_times,
            vec![TimeRange(10, 11)]
        );

        assert_eq!(
            test_input.meetings.get("2").unwrap().available_times,
            vec![TimeRange(0, 0), TimeRange(9, 11)]
        );

        assert_eq!(
            test_input.meetings.get("3").unwrap().available_times,
            vec![TimeRange(10, 11)]
        );

        assert_eq!(
            test_input.meetings.get("4").unwrap().available_times,
            vec![]
        );
    }

    #[test]
    fn find_availability() {
        let mut test_input = Input::new(
            vec![
                (
                    "0".to_string(),
                    Participant::new(vec![TimeRange(0, 0), TimeRange(2, 5), TimeRange(9, 9)]),
                ),
                (
                    "1".to_string(),
                    Participant::new(vec![TimeRange(1, 1), TimeRange(3, 3), TimeRange(7, 8)]),
                ),
                ("2".to_string(), Participant::new(vec![TimeRange(1, 8)])),
                ("3".to_string(), Participant::new(vec![])),
                ("4".to_string(), Participant::new(vec![TimeRange(0, 7)])),
                ("5".to_string(), Participant::new(vec![TimeRange(8, 12)])),
            ]
            .into_iter()
            .collect(),
            vec![
                (
                    "0".to_string(),
                    Meeting::new(1, vec!["0".to_string(), "1".to_string()]),
                ),
                (
                    "1".to_string(),
                    Meeting::new(2, vec!["0".to_string(), "1".to_string()]),
                ),
                (
                    "2".to_string(),
                    Meeting::new(1, vec!["1".to_string(), "2".to_string()]),
                ),
                (
                    "3".to_string(),
                    Meeting::new(1, vec!["0".to_string(), "1".to_string(), "2".to_string()]),
                ),
                (
                    "4".to_string(),
                    Meeting::new(1, vec!["4".to_string(), "5".to_string()]),
                ),
            ]
            .into_iter()
            .collect(),
            vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)],
        );

        assert!(test_input.sort().is_ok());
        let _ = test_input.get_user_availability();
        let _ = test_input.get_meeting_availability();

        let test_input: ScheduleInput = test_input.into();

        assert_eq!(
            schedule_meetings(&test_input, Some(100)),
            Err(ValidationError::NoSolution)
        );
        assert_eq!(
            schedule_meetings(&test_input, None),
            Err(ValidationError::NoSolution)
        );

        let mut test_input = Input::new(
            vec![
                ("a".to_string(), Participant::new(vec![TimeRange(3, 4)])),
                ("b".to_string(), Participant::new(vec![TimeRange(2, 4)])),
                (
                    "c".to_string(),
                    Participant::new(vec![TimeRange(0, 0), TimeRange(3, 4)]),
                ),
                (
                    "d".to_string(),
                    Participant::new(vec![TimeRange(0, 1), TimeRange(4, 4)]),
                ),
            ]
            .into_iter()
            .collect(),
            vec![
                ("0".to_string(), Meeting::new(1, vec!["a".to_string()])),
                ("1".to_string(), Meeting::new(1, vec!["b".to_string()])),
                ("2".to_string(), Meeting::new(1, vec!["c".to_string()])),
                ("3".to_string(), Meeting::new(1, vec!["d".to_string()])),
            ]
            .into_iter()
            .collect(),
            vec![TimeRange(0, 4)],
        );

        assert!(test_input.sort().is_ok());
        let _ = test_input.get_user_availability();
        let _ = test_input.get_meeting_availability();

        let test_input: ScheduleInput = test_input.into();
        assert!(schedule_meetings(&test_input, None).is_ok());
    }
}
