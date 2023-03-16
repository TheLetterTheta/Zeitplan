//! # Zeitplan Libs
//!
//! This is the core library for the Zeiplan Scheduling app.

#[cfg(feature = "wasm")]
use wasm_bindgen::prelude::*;

/// Meetings to be scheduled
pub mod meeting;

/// Participants of meetings
pub mod participant;

/// Holds the information for scheduling multiple meetings at once
pub mod schedule;

/// Utility functions for TimeRange. Used throughout the lib
pub mod time;

#[cfg(feature = "wasm")]
#[wasm_bindgen]
pub fn schedule(schedule: JsValue) -> Result<JsValue, JsValue> {
    use crate::schedule::Schedule;

    let schedule: Schedule<u16> = serde_wasm_bindgen::from_value(schedule)?;
    Ok(serde_wasm_bindgen::to_value(
        &schedule.schedule_meetings(None, None, None),
    )?)
}

#[cfg(feature = "wasm")]
#[wasm_bindgen]
pub fn get_meeting_availability(
    meeting: JsValue,
    available_times: JsValue,
) -> Result<JsValue, JsValue> {
    use crate::meeting::Meeting;
    use crate::time::{Available, TimeRange};

    let meeting: Meeting<u16> = serde_wasm_bindgen::from_value(meeting)?;
    let available_times: Vec<TimeRange<u16>> = serde_wasm_bindgen::from_value(available_times)?;

    Ok(serde_wasm_bindgen::to_value(
        &meeting.get_availability(&available_times),
    )?)
}

#[cfg(feature = "wasm")]
#[wasm_bindgen]
pub fn get_participant_availability(
    participant: JsValue,
    available_times: JsValue,
) -> Result<JsValue, JsValue> {
    use crate::participant::Participant;
    use crate::time::{Available, TimeRange};

    let participant: Participant<u16> = serde_wasm_bindgen::from_value(participant)?;
    let available_times: Vec<TimeRange<u16>> = serde_wasm_bindgen::from_value(available_times)?;

    Ok(serde_wasm_bindgen::to_value(
        &participant.get_availability(&available_times),
    )?)
}

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

        let unmerged_times: Vec<TimeRange<u8>> = vec![
            TimeRange::new(1, 1),
            TimeRange::new(2, 2),
            TimeRange::new(2, 9),
            TimeRange::new(3, 5),
            TimeRange::new(11, 11),
        ];

        assert_eq!(
            unmerged_times
                .iter()
                .time_merge()
                .into_iter()
                .collect::<Vec<_>>(),
            vec![TimeRange::new(1, 9), TimeRange::new(11, 11)]
        );
    }

    #[test]
    fn pigeon_count() {
        use crate::time::{Pigeons, TimeRange};

        let pigeon_set: Vec<TimeRange<u8>> = vec![TimeRange::new(1, 9), TimeRange::new(11, 11)];

        assert_eq!(pigeon_set.into_iter().count_pigeons(), Some(10));
    }

    #[test]
    fn gets_meeting_availability() {
        use crate::meeting::{Meeting, MeetingParticipants};
        use crate::participant::Participant;
        use crate::time::{Available, TimeRange};

        let blocked_times_1: Vec<TimeRange<u8>> = vec![
            TimeRange::new(1, 2),
            TimeRange::new(22, 22),
            TimeRange::new(4, 4),
        ];

        let blocked_times_2 = vec![TimeRange::new(24, 31), TimeRange::new(20, 21)];

        let participants = vec![
            Participant::new(&"1", blocked_times_1),
            Participant::new(&"2", blocked_times_2),
        ];

        let meeting: MeetingParticipants<u8> = MeetingParticipants::new(&"1", participants, 2);

        let meeting: Meeting<u8> = meeting.into();

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

        let available_time: Vec<TimeRange<u8>> = vec![
            TimeRange::new(0, 6),
            TimeRange::new(22, 24),
            TimeRange::new(30, 33),
        ];

        assert_eq!(
            available_time.iter().windowed(1).collect::<Vec<_>>(),
            vec![
                TimeRange::new(0, 0),
                TimeRange::new(1, 1),
                TimeRange::new(2, 2),
                TimeRange::new(3, 3),
                TimeRange::new(4, 4),
                TimeRange::new(5, 5),
                TimeRange::new(6, 6),
                TimeRange::new(22, 22),
                TimeRange::new(23, 23),
                TimeRange::new(24, 24),
                TimeRange::new(30, 30),
                TimeRange::new(31, 31),
                TimeRange::new(32, 32),
                TimeRange::new(33, 33),
            ]
        );
        assert_eq!(
            available_time.iter().windowed(2).collect::<Vec<_>>(),
            vec![
                TimeRange::new(0, 1),
                TimeRange::new(1, 2),
                TimeRange::new(2, 3),
                TimeRange::new(3, 4),
                TimeRange::new(4, 5),
                TimeRange::new(5, 6),
                TimeRange::new(22, 23),
                TimeRange::new(23, 24),
                TimeRange::new(30, 31),
                TimeRange::new(31, 32),
                TimeRange::new(32, 33)
            ]
        );
        assert_eq!(
            available_time.iter().windowed(3).collect::<Vec<_>>(),
            vec![
                TimeRange::new(0, 2),
                TimeRange::new(1, 3),
                TimeRange::new(2, 4),
                TimeRange::new(3, 5),
                TimeRange::new(4, 6),
                TimeRange::new(22, 24),
                TimeRange::new(30, 32),
                TimeRange::new(31, 33)
            ]
        );
        assert_eq!(
            available_time.iter().windowed(4).collect::<Vec<_>>(),
            vec![
                TimeRange::new(0, 3),
                TimeRange::new(1, 4),
                TimeRange::new(2, 5),
                TimeRange::new(3, 6),
                TimeRange::new(30, 33)
            ]
        );
    }

    #[test]
    fn schedules() {
        use crate::meeting::Meeting;
        use crate::schedule::Schedule;
        use crate::time::TimeRange;

        let meeting_1 = Meeting::new("1", vec![TimeRange::new(2, 5)], 1);
        let meeting_2 = Meeting::new("2", vec![TimeRange::new(0, 0), TimeRange::new(2, 5)], 1);
        let meeting_3 = Meeting::new("3", vec![TimeRange::new(0, 1), TimeRange::new(3, 5)], 1);
        let meeting_4 = Meeting::new("4", vec![TimeRange::new(0, 2), TimeRange::new(4, 5)], 1);
        let meeting_5 = Meeting::new("5", vec![TimeRange::new(0, 3), TimeRange::new(5, 5)], 1);

        let available_time = vec![TimeRange::new(0, 5)];

        let schedule: Schedule<u8> = Schedule::new(
            vec![
                meeting_1.clone(),
                meeting_2.clone(),
                meeting_3.clone(),
                meeting_4.clone(),
                meeting_5.clone(),
            ],
            available_time.clone(),
        );

        assert!(schedule.schedule_meetings(None, None, None).is_ok());

        let meeting_6 = Meeting::new("6", vec![TimeRange::new(0, 3), TimeRange::new(5, 5)], 1);

        let schedule = Schedule::new(
            vec![
                meeting_1, meeting_2, meeting_3, meeting_4, meeting_5, meeting_6,
            ],
            available_time,
        );
        assert!(schedule.schedule_meetings(None, None, None).is_err());

        let schedule: Schedule<u16> = Schedule::new(
            vec![
                Meeting::new("1", vec![TimeRange::new(1, 1000)], 1),
                Meeting::new("2", vec![TimeRange::new(1, 1000)], 1),
                Meeting::new("3", vec![], 1),
                Meeting::new("4", vec![], 1),
                Meeting::new("5", vec![], 1),
                Meeting::new("6", vec![], 1),
                Meeting::new("7", vec![], 1),
            ],
            vec![TimeRange::new(0, 1000)],
        );

        assert!(schedule.schedule_meetings(None, None, None).is_err());
    }
}
