use criterion::{black_box, criterion_group, criterion_main, Criterion};
use std::collections::HashMap;
use zeitplan_libs::{Input, Meeting, Participant, TimeRange};

fn sort_and_schedule(c: &mut Criterion) {
    c.bench_function("validate", |b| {
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
            (0..300).map(|_| TimeRange(0, 0)).collect(),
        );

        b.iter(|| black_box(test_input.validate()));
    });

    c.bench_function("sort_input", |b| {
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

        test_input.validate();

        b.iter(|| black_box(test_input.sort()))
    });

    c.bench_function("get_availability", move |b| {
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

        test_input.sort();

        b.iter(|| black_box(test_input.get_user_availability()))
    });

    c.bench_function("Get meeting availability", move |b| {
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
            vec![
                (
                    "0".to_string(),
                    Meeting::new(1, vec!["0".to_string(), "1".to_string()]),
                ),
                (
                    "1".to_string(),
                    Meeting::new(1, vec!["1".to_string(), "2".to_string()]),
                ),
                (
                    "2".to_string(),
                    Meeting::new(1, vec!["2".to_string(), "3".to_string()]),
                ),
                (
                    "3".to_string(),
                    Meeting::new(1, vec!["3".to_string(), "4".to_string()]),
                ),
                (
                    "4".to_string(),
                    Meeting::new(1, vec!["4".to_string(), "5".to_string()]),
                ),
                (
                    "5".to_string(),
                    Meeting::new(
                        1,
                        vec![
                            "0".to_string(),
                            "1".to_string(),
                            "2".to_string(),
                            "3".to_string(),
                            "4".to_string(),
                            "5".to_string(),
                        ],
                    ),
                ),
            ]
            .into_iter()
            .collect(),
            vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)],
        );

        test_input.get_user_availability();

        b.iter(|| black_box(test_input.get_meeting_availability()))
    });

    c.bench_function("cleanup", move |b| {
        let mut test_input = Input::new(HashMap::new(), HashMap::new(), Vec::new());

        test_input.get_meeting_availability();

        b.iter(|| black_box(test_input.clone()));
    });
}

criterion_group!(benches, sort_and_schedule);
criterion_main!(benches);
