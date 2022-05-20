use criterion::{black_box, criterion_group, criterion_main, BatchSize, Criterion};
use zeitplan_libs::meeting::{Meeting, MeetingParticipants};
use zeitplan_libs::participant::Participant;
use zeitplan_libs::schedule::Schedule;
use zeitplan_libs::time::{Available, Pigeons, TimeMerge, TimeRange, Windowed};

fn get_participant_avaiability(c: &mut Criterion) {
    let blocked_times = vec![
        TimeRange::new(1, 2),
        TimeRange::new(4, 4),
        TimeRange::new(20, 22),
        TimeRange::new(24, 31),
    ];
    let participant: Participant<u8> = Participant::new(&"1", blocked_times);

    let available_time = vec![
        TimeRange::new(0, 9),
        TimeRange::new(22, 24),
        TimeRange::new(30, 35),
    ];

    c.bench_function("gets_participant_availability", |b| {
        b.iter_batched(
            || participant.clone(),
            |data| black_box(data.get_availability(&available_time)),
            BatchSize::SmallInput,
        )
    });
}

fn merge_times(c: &mut Criterion) {
    let input = vec![
        TimeRange::new(1, 1),
        TimeRange::new(1, 1),
        TimeRange::new(2, 3),
        TimeRange::new(5, 7),
        TimeRange::new(6, 7),
        TimeRange::new(7, 7),
    ];

    c.bench_function("merge_times", |b| {
        b.iter(|| black_box(input.iter().time_merge()))
    });
}

fn pigeon_count(c: &mut Criterion) {
    let pigeon_set: Vec<TimeRange<u8>> = vec![TimeRange::new(1, 9), TimeRange::new(11, 11)];

    c.bench_function("pigeon_count", |b| {
        b.iter_batched(
            || pigeon_set.clone(),
            |data| black_box(data.into_iter().count_pigeons()),
            BatchSize::SmallInput,
        )
    });
}

fn get_meeting_availability(c: &mut Criterion) {
    let blocked_times_1 = vec![
        TimeRange::new(1, 2),
        TimeRange::new(22, 22),
        TimeRange::new(4, 4),
    ];

    let blocked_times_2 = vec![TimeRange::new(24, 31), TimeRange::new(20, 21)];

    let participants: Vec<Participant<u8>> = vec![
        Participant::new(&"1", blocked_times_1),
        Participant::new(&"2", blocked_times_2),
    ];

    let meeting = MeetingParticipants::new(&"1", participants, 2);
    let meeting: Meeting<u8> = meeting.into();

    let available_time = vec![
        TimeRange::new(0, 9),
        TimeRange::new(22, 24),
        TimeRange::new(30, 35),
    ];

    c.bench_function("gets_meeting_availability", |b| {
        b.iter_batched(
            || meeting.clone(),
            |data| black_box(data.get_availability(&available_time)),
            BatchSize::SmallInput,
        );
    });
}

fn windows(c: &mut Criterion) {
    let available_time = vec![
        TimeRange::new(0, 6),
        TimeRange::new(22, 24),
        TimeRange::new(30, 33),
    ];

    c.bench_function("windows", |b| {
        b.iter(|| black_box(available_time.iter().windowed(1)));
    });
}

fn schedules(c: &mut Criterion) {
    let meeting_1 = Meeting::new("1", vec![TimeRange::new(2, 5)], 1);
    let meeting_2 = Meeting::new("2", vec![TimeRange::new(0, 0), TimeRange::new(2, 5)], 1);
    let meeting_3 = Meeting::new("3", vec![TimeRange::new(0, 1), TimeRange::new(3, 5)], 1);
    let meeting_4 = Meeting::new("4", vec![TimeRange::new(0, 2), TimeRange::new(4, 5)], 1);
    let meeting_5 = Meeting::new("5", vec![TimeRange::new(0, 3), TimeRange::new(5, 5)], 1);

    let available_time = vec![TimeRange::new(0, 5)];

    let schedule = Schedule::new(
        vec![
            meeting_1.clone(),
            meeting_2.clone(),
            meeting_3.clone(),
            meeting_4.clone(),
            meeting_5.clone(),
        ],
        available_time.clone(),
    );

    c.bench_function("schedules_simple", |b| {
        b.iter(|| black_box(schedule.schedule_meetings(None)));
    });

    let meeting_6 = Meeting::new("6", vec![TimeRange::new(0, 3), TimeRange::new(5, 5)], 1);

    let schedule = Schedule::new(
        vec![
            meeting_1, meeting_2, meeting_3, meeting_4, meeting_5, meeting_6,
        ],
        available_time,
    );

    c.bench_function("schedules_impossible", |b| {
        b.iter(|| black_box(schedule.schedule_meetings(None)));
    });

    // this will run for a long time since it's impossible, but not detected

    let schedule = Schedule::new(
        vec![
            Meeting::new("1", vec![TimeRange::new(1, 1000)], 1),
            Meeting::new("2", vec![TimeRange::new(1, 1000)], 1),
            Meeting::new("3", vec![], 1),
            Meeting::new("4", vec![], 1),
            Meeting::new("5", vec![], 1),
            Meeting::new("6", vec![], 1),
            Meeting::new("7", vec![], 1),
            Meeting::new("8", vec![], 1),
            Meeting::new("9", vec![], 1),
            Meeting::new("10", vec![], 1),
            Meeting::new("11", vec![], 1),
            Meeting::new("12", vec![], 1),
            Meeting::new("13", vec![], 1),
            Meeting::new("14", vec![], 1),
            Meeting::new("15", vec![], 1),
            Meeting::new("16", vec![], 1),
            Meeting::new("17", vec![], 1),
            Meeting::new("18", vec![], 1),
            Meeting::new("19", vec![], 1),
            Meeting::new("20", vec![], 1),
        ],
        vec![TimeRange::new(0, 1000)],
    );

    c.bench_function("schedules_impossible_hard", |b| {
        b.iter(|| black_box(schedule.schedule_meetings(None)));
    });

    let schedule = Schedule::new(
        vec![
            Meeting::new("1", vec![TimeRange::new(1, 1000)], 1),
            Meeting::new("2", vec![TimeRange::new(1, 1000)], 1),
            Meeting::new("3", vec![], 1),
            Meeting::new("4", vec![], 1),
            Meeting::new("5", vec![], 1),
            Meeting::new("6", vec![], 1),
            Meeting::new("7", vec![], 1),
            Meeting::new("8", vec![], 1),
            Meeting::new("9", vec![], 1),
            Meeting::new("10", vec![], 1),
            Meeting::new("11", vec![], 1),
            Meeting::new("12", vec![], 1),
            Meeting::new("13", vec![], 1),
            Meeting::new("14", vec![], 1),
            Meeting::new("15", vec![], 1),
            Meeting::new("16", vec![], 1),
            Meeting::new("17", vec![], 1),
            Meeting::new("18", vec![], 1),
            Meeting::new("19", vec![], 1),
            Meeting::new("20", vec![], 1),
        ],
        vec![TimeRange::new(0, 1001)],
    );

    c.bench_function("schedules_possible_hard", |b| {
        b.iter(|| black_box(schedule.schedule_meetings(None)));
    });
}

criterion_group! {
    name = benches;
    config = Criterion::default().significance_level(0.05).sample_size(1000);
    targets = schedules,
    get_participant_avaiability,
    merge_times,
    pigeon_count,
    windows,
    get_meeting_availability
}

criterion_main!(benches);
