use criterion::{black_box, criterion_group, criterion_main, Criterion};
use zeitplan_libs::{Input, Meeting, Participant, TimeRange};

fn sort_and_schedule(c: &mut Criterion) {
    c.bench_function("sort_input", |b| {
        let mut test_input = Input::new(
            vec![
                Participant::new(
                    "0".to_string(),
                    vec![TimeRange(0, 0), TimeRange(2, 5), TimeRange(9, 9)],
                ),
                Participant::new(
                    "1".to_string(),
                    vec![TimeRange(1, 1), TimeRange(3, 3), TimeRange(7, 8)],
                ),
                Participant::new("2".to_string(), vec![TimeRange(1, 8)]),
                Participant::new("3".to_string(), vec![]),
                Participant::new("4".to_string(), vec![TimeRange(2, 7)]),
                Participant::new("5".to_string(), vec![TimeRange(9, 9)]),
            ],
            vec![],
            vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)],
        );

        b.iter(|| black_box(test_input.sort()))
    });

    c.bench_function("get_availability", move |b| {
        let mut test_input = Input::new(
            vec![
                Participant::new(
                    "0".to_string(),
                    vec![TimeRange(0, 0), TimeRange(2, 5), TimeRange(9, 9)],
                ),
                Participant::new(
                    "1".to_string(),
                    vec![TimeRange(1, 1), TimeRange(3, 3), TimeRange(7, 8)],
                ),
                Participant::new("2".to_string(), vec![TimeRange(1, 8)]),
                Participant::new("3".to_string(), vec![]),
                Participant::new("4".to_string(), vec![TimeRange(2, 7)]),
                Participant::new("5".to_string(), vec![TimeRange(9, 9)]),
            ],
            vec![],
            vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)],
        );

        test_input.sort();

        b.iter(|| black_box(test_input.get_user_availability()))
    });

    c.bench_function("get_availability", move |b| {
        let mut test_input = Input::new(
            vec![
                Participant::new(
                    "0".to_string(),
                    vec![TimeRange(0, 0), TimeRange(2, 5), TimeRange(9, 9)],
                ),
                Participant::new(
                    "1".to_string(),
                    vec![TimeRange(1, 1), TimeRange(3, 3), TimeRange(7, 8)],
                ),
                Participant::new("2".to_string(), vec![TimeRange(1, 8)]),
                Participant::new("3".to_string(), vec![]),
                Participant::new("4".to_string(), vec![TimeRange(2, 7)]),
                Participant::new("5".to_string(), vec![TimeRange(9, 9)]),
            ],
            vec![
                Meeting::new("0".to_string(), 1, vec!["0".to_string(), "1".to_string()]),
                Meeting::new("1".to_string(), 1, vec!["1".to_string(), "2".to_string()]),
                Meeting::new("2".to_string(), 1, vec!["2".to_string(), "3".to_string()]),
                Meeting::new("3".to_string(), 1, vec!["3".to_string(), "4".to_string()]),
                Meeting::new("4".to_string(), 1, vec!["4".to_string(), "5".to_string()]),
                Meeting::new(
                    "5".to_string(),
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
            ],
            vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)],
        );

        test_input.sort();
        test_input.get_user_availability();

        b.iter(|| black_box(test_input.get_meeting_availability()))
    });
}

criterion_group!(benches, sort_and_schedule);
criterion_main!(benches);
