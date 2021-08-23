use wasm_bindgen::prelude::*;

mod meeting;
mod participant;
mod schedule;
mod time;

/*
#[wasm_bindgen]                                                                                  ║
pub fn schedule(value: JsValue) -> Result<JsValue, JsValue> {
    use crate::schedule::Schedule;

    let value: Schedule<u16> = serde_wasm_bindgen::from_value(value)?;
    Ok(serde_wasm_bindgen::to_value(&value.schedule_meetings(None)).unwrap())
}
*/


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
        use crate::meeting::Meeting;
        use crate::participant::Participant;
        use crate::schedule::Schedule;
        use crate::time::TimeRange;

        let user_1 = Participant::new("1", vec![TimeRange::new(2, 5)]);
        let user_2 = Participant::new("2", vec![TimeRange::new(0, 0), TimeRange::new(2, 5)]);
        let user_3 = Participant::new("3", vec![TimeRange::new(0, 1), TimeRange::new(3, 5)]);
        let user_4 = Participant::new("4", vec![TimeRange::new(0, 2), TimeRange::new(4, 5)]);
        let user_5 = Participant::new("5", vec![TimeRange::new(0, 3), TimeRange::new(5, 5)]);

        let meeting_1 = Meeting::new("1", vec![user_1], 1);
        let meeting_2 = Meeting::new("2", vec![user_2], 1);
        let meeting_3 = Meeting::new("3", vec![user_3], 1);
        let meeting_4 = Meeting::new("4", vec![user_4], 1);
        let meeting_5 = Meeting::new("5", vec![user_5.clone()], 1);

        let available_time = vec![
            TimeRange::new(0, 5),
        ];

        let schedule = Schedule::new(
            vec![meeting_1.clone(), meeting_2.clone(), meeting_3.clone(), meeting_4.clone(), meeting_5.clone()],
            available_time.clone(),
        );

        assert!(schedule.schedule_meetings(None).is_ok());

        let meeting_6 = Meeting::new("6", vec![user_5.clone()], 1);

        let schedule = Schedule::new(
            vec![meeting_1, meeting_2, meeting_3, meeting_4, meeting_5, meeting_6],
            available_time,
        );
        assert!(schedule.schedule_meetings(None).is_err());


        // this will run for a long time since it's impossible, but not detected
        let user_1 = Participant::new("1", vec![TimeRange::new(1, 1000)]);
        let user_2 = Participant::new("2", vec![TimeRange::new(1, 1000)]);
        let user_3 = Participant::new("3", vec![]);
        let user_4 = Participant::new("4", vec![]);
        let user_5 = Participant::new("5", vec![]);
        let user_6 = Participant::new("6", vec![]);
        let user_7 = Participant::new("7", vec![]);

        let schedule = Schedule::new(
            vec![
                Meeting::new("1", vec![user_1], 1),
                Meeting::new("2", vec![user_2], 1),
                Meeting::new("3", vec![user_3], 1),
                Meeting::new("4", vec![user_4], 1),
                Meeting::new("5", vec![user_5], 1),
                Meeting::new("6", vec![user_6], 1),
                Meeting::new("7", vec![user_7], 1),
            ],
            vec![TimeRange::new(0, 1000)]
            );

        assert!(schedule.schedule_meetings(None).is_err());
    }
}
