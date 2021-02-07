use criterion::{black_box, criterion_group, criterion_main, Criterion};
use zeitplan_libs::{Input, Meeting, Participant, TimeRange};

fn sort_and_schedule(c: &mut Criterion) {
    c.bench_function("sort_input", |b| {
        let mut test_input = Input {
            participants: vec![
                Participant {
                    id: "0".to_string(),
                    blocked_times: vec![TimeRange(0, 0), TimeRange(2, 5), TimeRange(9, 9)],
                    available_times: vec![],
                },
                Participant {
                    id: "1".to_string(),
                    blocked_times: vec![TimeRange(1, 1), TimeRange(3, 3), TimeRange(7, 8)],
                    available_times: vec![],
                },
                Participant {
                    id: "2".to_string(),
                    blocked_times: vec![TimeRange(1, 8)],
                    available_times: vec![],
                },
                Participant {
                    id: "3".to_string(),
                    blocked_times: vec![],
                    available_times: vec![],
                },
                Participant {
                    id: "4".to_string(),
                    blocked_times: vec![TimeRange(2, 7)],
                    available_times: vec![],
                },
                Participant {
                    id: "5".to_string(),
                    blocked_times: vec![TimeRange(9, 9)],
                    available_times: vec![],
                },
            ],
            meetings: vec![],
            available_time_range: vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)],
            is_sorted: false,
        };

        b.iter(|| black_box(test_input.sort()))
    });

    c.bench_function("get_availability", move |b| {
        let mut test_input = Input {
            participants: vec![
                Participant {
                    id: "0".to_string(),
                    blocked_times: vec![TimeRange(0, 0), TimeRange(2, 5), TimeRange(9, 9)],
                    available_times: vec![],
                },
                Participant {
                    id: "1".to_string(),
                    blocked_times: vec![TimeRange(1, 1), TimeRange(3, 3), TimeRange(7, 8)],
                    available_times: vec![],
                },
                Participant {
                    id: "2".to_string(),
                    blocked_times: vec![TimeRange(1, 8)],
                    available_times: vec![],
                },
                Participant {
                    id: "3".to_string(),
                    blocked_times: vec![],
                    available_times: vec![],
                },
                Participant {
                    id: "4".to_string(),
                    blocked_times: vec![TimeRange(2, 7)],
                    available_times: vec![],
                },
                Participant {
                    id: "5".to_string(),
                    blocked_times: vec![TimeRange(9, 9)],
                    available_times: vec![],
                },
            ],
            meetings: vec![],
            available_time_range: vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)],
            is_sorted: false,
        };

        test_input.sort();

        b.iter(|| black_box(test_input.get_user_availability()))
    });

    c.bench_function("get_availability", move |b| {
        let mut test_input = Input {
            participants: vec![
                Participant {
                    id: "0".to_string(),
                    blocked_times: vec![TimeRange(0, 0), TimeRange(2, 5), TimeRange(9, 9)],
                    available_times: vec![],
                },
                Participant {
                    id: "1".to_string(),
                    blocked_times: vec![TimeRange(1, 1), TimeRange(3, 3), TimeRange(7, 8)],
                    available_times: vec![],
                },
                Participant {
                    id: "2".to_string(),
                    blocked_times: vec![TimeRange(1, 8)],
                    available_times: vec![],
                },
                Participant {
                    id: "3".to_string(),
                    blocked_times: vec![],
                    available_times: vec![],
                },
                Participant {
                    id: "4".to_string(),
                    blocked_times: vec![TimeRange(2, 7)],
                    available_times: vec![],
                },
                Participant {
                    id: "5".to_string(),
                    blocked_times: vec![TimeRange(9, 9)],
                    available_times: vec![],
                },
            ],
            meetings: vec![
                Meeting {
                    id: "0".to_string(),
                    duration: 1,
                    participant_ids: vec!["0".to_string(), "1".to_string()],
                    available_times: vec![],
                },
                Meeting {
                    id: "1".to_string(),
                    duration: 1,
                    participant_ids: vec!["1".to_string(), "2".to_string()],
                    available_times: vec![],
                },
                Meeting {
                    id: "2".to_string(),
                    duration: 1,
                    participant_ids: vec!["2".to_string(), "3".to_string()],
                    available_times: vec![],
                },
                Meeting {
                    id: "3".to_string(),
                    duration: 1,
                    participant_ids: vec!["3".to_string(), "4".to_string()],
                    available_times: vec![],
                },
                Meeting {
                    id: "4".to_string(),
                    duration: 1,
                    participant_ids: vec!["4".to_string(), "5".to_string()],
                    available_times: vec![],
                },
                Meeting {
                    id: "5".to_string(),
                    duration: 1,
                    participant_ids: vec![
                        "0".to_string(),
                        "1".to_string(),
                        "2".to_string(),
                        "3".to_string(),
                        "4".to_string(),
                        "5".to_string(),
                    ],
                    available_times: vec![],
                },
            ],
            available_time_range: vec![TimeRange(0, 1), TimeRange(3, 6), TimeRange(8, 11)],
            is_sorted: false,
        };

        test_input.sort();
        test_input.get_user_availability();

        b.iter(|| black_box(test_input.get_meeting_availability()))
    });
}

criterion_group!(benches, sort_and_schedule);
criterion_main!(benches);
