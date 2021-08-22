mod meeting;
mod participant;
mod schedule;
mod time;

#[cfg(test)]
mod tests {

    #[test]
    fn gets_participant_availability() {
        use crate::participant::Participant;
        use crate::time::{Available, TimeRange};

        let blocked_times = vec![
            TimeRange::new(1, 2),
            TimeRange::new(4, 4),
            TimeRange::new(20, 22),
            TimeRange::new(24, 31),
        ];
        let participant = Participant::new(&"1", blocked_times);

        let available_time = vec![
            TimeRange::new(0, 9),
            TimeRange::new(22, 24),
            TimeRange::new(30, 35),
        ];

        assert_eq!(
            participant.get_availability(&available_time),
            vec![
                TimeRange::new(0, 0),
                TimeRange::new(3, 3),
                TimeRange::new(5, 9),
                TimeRange::new(23, 23),
                TimeRange::new(32, 35),
            ]
        );
    }

    #[test]
    fn merge_times() {
        use crate::time::{TimeMerge, TimeRange};

        let unmerged_times = vec![
            TimeRange::new(1, 1),
            TimeRange::new(2, 2),
            TimeRange::new(2, 9),
            TimeRange::new(3, 5),
            TimeRange::new(11, 11),
        ];

        assert_eq!(
            dbg!(unmerged_times.iter().time_merge()),
            vec![TimeRange::new(1, 9), TimeRange::new(11, 11)]
        );
    }

    #[test]
    fn pigeon_count() {
        use crate::time::{Pigeons, TimeRange};

        let pigeon_set = vec![TimeRange::new(1, 9), TimeRange::new(11, 11)];

        assert_eq!(pigeon_set.iter().count_pigeons(), 10);
    }

    #[test]
    fn gets_meeting_availability() {
        use crate::meeting::Meeting;
        use crate::participant::Participant;
        use crate::time::{Available, TimeRange};

        let blocked_times_1 = vec![
            TimeRange::new(1, 2),
            TimeRange::new(22, 22),
            TimeRange::new(4, 4),
        ];

        let blocked_times_2 = vec![TimeRange::new(24, 31), TimeRange::new(20, 21)];

        let participants = vec![
            Participant::new(&"1", blocked_times_1),
            Participant::new(&"2", blocked_times_2),
        ];

        let meeting = Meeting::new(&"1", participants, 2);

        let available_time = vec![
            TimeRange::new(0, 9),
            TimeRange::new(22, 24),
            TimeRange::new(30, 35),
        ];

        assert_eq!(
            meeting.get_availability(&available_time),
            vec![TimeRange::new(5, 9), TimeRange::new(32, 35)]
        );
    }

    #[test]
    fn windows() {
        use crate::time::{TimeRange, Windowed};

        let available_time = vec![
            TimeRange::new(0, 6),
            TimeRange::new(22, 24),
            TimeRange::new(30, 33),
        ];

        assert_eq!(
            available_time.iter().windowed(1),
            vec![
                TimeRange(0, 0),
                TimeRange(1, 1),
                TimeRange(2, 2),
                TimeRange(3, 3),
                TimeRange(4, 4),
                TimeRange(5, 5),
                TimeRange(6, 6),
                TimeRange(22, 22),
                TimeRange(23, 23),
                TimeRange(24, 24),
                TimeRange(30, 30),
                TimeRange(31, 31),
                TimeRange(32, 32),
                TimeRange(33, 33),
            ]
        );
        assert_eq!(
            available_time.iter().windowed(2),
            vec![
                TimeRange(0, 1),
                TimeRange(1, 2),
                TimeRange(2, 3),
                TimeRange(3, 4),
                TimeRange(4, 5),
                TimeRange(5, 6),
                TimeRange(22, 23),
                TimeRange(23, 24),
                TimeRange(30, 31),
                TimeRange(31, 32),
                TimeRange(32, 33)
            ]
        );
        assert_eq!(
            available_time.iter().windowed(3),
            vec![
                TimeRange(0, 2),
                TimeRange(1, 3),
                TimeRange(2, 4),
                TimeRange(3, 5),
                TimeRange(4, 6),
                TimeRange(22, 24),
                TimeRange(30, 32),
                TimeRange(31, 33)
            ]
        );
        assert_eq!(
            available_time.iter().windowed(4),
            vec![
                TimeRange(0, 3),
                TimeRange(1, 4),
                TimeRange(2, 5),
                TimeRange(3, 6),
                TimeRange(30, 33)
            ]
        );
    }

    #[test]
    fn schedules() {
        use crate::schedule::Schedule;
        use crate::time::TimeRange;

        let available_time = vec![
            TimeRange::new(0, 9),
            TimeRange::new(22, 24),
            TimeRange::new(30, 35),
        ];

        let _schedule = Schedule::new(vec![], available_time);
    }
}
