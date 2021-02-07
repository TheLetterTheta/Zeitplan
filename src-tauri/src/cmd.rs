use itertools::Itertools;
#[allow(non_snake_case)]
use rayon::prelude::*;
use serde::Deserialize;
use serde::Serialize;
use std::collections::{BinaryHeap, HashMap, HashSet};

pub struct MeetingProcessing {
    pub id: String,
    pub available_times: Option<HashSet<u16>>,
    pub duration: usize,
}

#[derive(Debug, Clone, Serialize)]
pub struct MeetingTimeslot {
    start: u16,
    length: u16,
}

#[derive(Serialize)]
enum ScheduledStatus {
    UnableToSchedule,
    Scheduled,
}

struct ScheduledMeeting {
    meeting: MeetingProcessing,
    nth_meeting: Vec<u16>,
    able_to_schedule: ScheduledStatus,
}

#[derive(Serialize)]
pub struct Schedule {
    id: String,
    times: Vec<u16>,
    status: ScheduledStatus,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct User {
    pub id: String,
    pub events: Vec<u16>,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct Meeting {
    pub id: String,
    pub duration: usize,
    pub participant_ids: Vec<String>,
    title: String,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ComputeMeetingSpacePayload {
    pub users: Vec<User>,
    pub meetings: Vec<Meeting>,
    pub available_time_range: Vec<u16>,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct KeyValue {
    pub key: String,
    pub value: String,
}

#[derive(Deserialize)]
#[serde(tag = "cmd", rename_all = "camelCase")]
pub enum Cmd {
    // your custom commands
    // multiple arguments are allowed
    // note that rename_all = "camelCase": you need to use "myCustomCommand" on JS
    ComputeMeetingSpace {
        payload: ComputeMeetingSpacePayload,
        callback: String,
        error: String,
    },
    ComputeScheduleFromMeetings {
        payload: ComputeMeetingSpacePayload,
        callback: String,
        error: String,
    },
    ComputeAllMeetingCombinations {
        payload: ComputeMeetingSpacePayload,
        callback: String,
        error: String,
    },
    GetKey {
        payload: String,
        callback: String,
        error: String,
    },
    SetKey {
        payload: KeyValue,
        callback: String,
        error: String,
    },
    DeleteKey {
        payload: String,
        callback: String,
        error: String,
    },
}

impl ComputeMeetingSpacePayload {
    pub fn get_meeting_availability(self) -> Vec<MeetingProcessing> {
        // First convert the available timerange into a Set. This will be useful in the
        // next step when searching for a user's given availability
        let available_times: HashSet<_> = self.available_time_range.into_par_iter().collect();

        // The `self.users` is a collection of "blocked-out" times that the user is
        // unavailable. We need to get their avaiability against the master schedule
        // sheet to use when scheduling meetings. This is a simple Set Difference
        // between the `master_schedule - user_blocked_out_times`. We first need to
        // convert the user events into a Set, and return a HashMap that can be used
        // for lookups.
        let user_availability = self
            .users
            .into_par_iter()
            .map(|u| {
                let id = u.id;
                let user_unavailable_times: HashSet<_> = u.events.into_par_iter().collect();
                let user_can_schedule_for: HashSet<_> = available_times
                    .difference(&user_unavailable_times)
                    .cloned()
                    .collect();

                (id, user_can_schedule_for)
            })
            .collect::<HashMap<_, _>>();

        // Now for each meeting, we need to get the participant's schedule. There can
        // be multiple participants to a given meeting, and we need to pull in their
        // availability. The intersection of their availability is the times that the
        // meeting could be scheduled.
        self.meetings
            .into_par_iter()
            .map(|m| MeetingProcessing {
                id: m.id,
                available_times: m
                    .participant_ids
                    .into_par_iter()
                    // Get the user's schedule
                    .filter_map(|id| user_availability.get(&id))
                    .map(|v| v.clone()) // Clone is cheap
                    // Accumulate a set of available times that are the interseciton of
                    // user schedules
                    .reduce_with(|available_schedule, user_availability| {
                        if available_schedule.is_empty() {
                            available_schedule
                        } else {
                            available_schedule
                                .intersection(&user_availability)
                                // Copied is expensive, but needs to
                                // happen since we are duplicating the
                                // values. This should be a subset of the
                                // elements anyway.
                                .copied()
                                .collect()
                        }
                    })
                    // Return None if there are no available meeting times
                    .map(|r| if r.is_empty() { None } else { Some(r) })
                    .flatten(),
                duration: m.duration,
            })
            .collect::<Vec<_>>()
    }

    pub fn compute(self) -> Vec<Schedule> {
        let mut meeting_available_times: Vec<MeetingProcessing> = self.get_meeting_availability();

        // Order the meetings by the least available first. This should be processed
        // first, as it is the most likely to cause conflicts if scheduled later
        meeting_available_times.par_sort_unstable_by(|a, b| {
            a.available_times
                .as_ref()
                .map(|l| l.len())
                .unwrap_or(0)
                .cmp(&b.available_times.as_ref().map(|l| l.len()).unwrap_or(0))
        });

        // We will need to be able to push to the front and back of the resulting
        // vector. We cast it to a VecDeque, and enqueue all current meetings. When we
        // encounter a meeting that cannot be scheduled, we can push_front the previous
        // meeting (which should be the next-most available meeting by times)
        // let mut meeting_available_times = Vec::from(meeting_available_times);

        // We will use this to track the "scheduled" meetings so far. We will also use
        // this as a stack to undo the last scheduled meeting to re-enqueue it to the
        //// meeting_available_times. We can reserve the capacity to be the number of
        // meetings that need to be scheduled.
        let mut scheduled_stack: Vec<ScheduledMeeting> =
            Vec::with_capacity(meeting_available_times.len());
        let mut scheduled_event_set: HashSet<u16> =
            HashSet::with_capacity(meeting_available_times.len());

        for not_scheduled in meeting_available_times {
            match not_scheduled.available_times {
                Some(ref timespans) => {
                    let mut remaining_timespans: Vec<u16> = timespans
                        .difference(&scheduled_event_set)
                        .cloned()
                        .collect();

                    remaining_timespans.par_sort_unstable();

                    match remaining_timespans
                        .par_windows(not_scheduled.duration)
                        .find_any(|window| {
                            window.len() <= 1
                                || match (window.first(), window.last()) {
                                    (Some(first), Some(&last)) => {
                                        last == first - 1 + window.len() as u16
                                    }
                                    _ => false,
                                }
                        }) {
                        Some(available_timeslot) => {
                            for time in available_timeslot {
                                scheduled_event_set.insert(*time);
                            }

                            scheduled_stack.push(ScheduledMeeting {
                                meeting: not_scheduled,
                                nth_meeting: Vec::from(available_timeslot),
                                able_to_schedule: ScheduledStatus::Scheduled,
                            });
                        }
                        None => {
                            // TODO: Couldn't schedule, but not because there are no
                            // available times. Try to re-enqueue the last scheduled
                            // event.
                            scheduled_stack.push(ScheduledMeeting {
                                meeting: not_scheduled,
                                nth_meeting: Vec::new(),
                                able_to_schedule: ScheduledStatus::UnableToSchedule,
                            });
                        }
                    }
                }
                None => {
                    scheduled_stack.push(ScheduledMeeting {
                        meeting: not_scheduled,
                        nth_meeting: Vec::new(),
                        able_to_schedule: ScheduledStatus::UnableToSchedule,
                    });
                }
            }
        }

        scheduled_stack
            .into_par_iter()
            .map(|m| Schedule {
                id: m.meeting.id,
                times: m.nth_meeting,
                status: m.able_to_schedule,
            })
            .collect::<Vec<_>>()
    }

    pub fn compute_all_possible_timespans(self) -> Option<Vec<(String, (u16, u16))>> {
        let mut meeting_available_times: Vec<MeetingProcessing> = self.get_meeting_availability();

        // Order the meetings by the least available first. This should be processed
        // first, as it is the most likely to cause conflicts if scheduled later
        meeting_available_times.par_sort_unstable_by(|a, b| {
            a.available_times
                .as_ref()
                .map(|l| l.len())
                .unwrap_or(0)
                .cmp(&b.available_times.as_ref().map(|l| l.len()).unwrap_or(0))
        });

        meeting_available_times
            // Split into parallel chunks
            .into_par_iter()
            // For each meeting, generate a Vec<(Start: u16, End: u16)> of times that *can* be
            // scheduled. This is not very memory efficient.
            .filter_map(|meeting: MeetingProcessing| {
                match meeting.available_times {
                    // There were no available times to begin with. Skip this meeting automatically
                    None => None,
                    Some(ref available_times) => {
                        // Sort the times and generate the (Start, End) tuple.
                        let times = as_timechunks(
                            available_times.into_par_iter().cloned().collect(),
                            meeting.duration,
                        );

                        // Though some times existed, there were not enough *consecutive* times to
                        // meet the duration criteria. Skip this meeting in all future processing.
                        if times.is_empty() {
                            None
                        } else {
                            Some(
                                times
                                    .into_par_iter()
                                    .map(|t| (meeting.id.clone(), t))
                                    .collect::<Vec<_>>(),
                            )
                        }
                    }
                }
            })
            // Use `collect::<>()` to `fuse` the parallel iterator so that we can use the
            // `itertools::multi_cartesian_product()` method for producing our comparison set.
            .collect::<Vec<_>>()
            .into_iter()
            .multi_cartesian_product()
            // Then re-parallelize it to speed up this process
            .par_bridge()
            // Return any valid criteria. In parallel, this makes no assertion to the nth
            // configuration that is returned here.
            .find_any(|t| is_valid_configuration(t))
    }
}

fn as_timechunks(mut input: Vec<u16>, duration: usize) -> Vec<(u16, u16)> {
    // We need to ensure consecutive times. This is being collected from a HashSet, which means we
    // can't make any gurantees about the order at this point.
    input.par_sort_unstable();
    input
        .par_windows(duration)
        .filter_map(|w| match (w.first(), w.last()) {
            (Some(first), Some(last)) if last == &(first + duration as u16 - 1) => {
                Some((first.clone(), last.clone()))
            }
            _ => None,
        })
        .collect()
}

fn is_valid_configuration(times: &Vec<(String, (u16, u16))>) -> bool {
    let mut timespans = times.iter().map(|t| t.1).collect::<Vec<_>>();

    // Sorting the list gives a O(n+log(n)), which isn't great, but is much better than checking
    // every time against every other time O(n^2).
    timespans.par_sort_unstable_by(|a, b| a.0.cmp(&b.0));

    // Because they are consecutive at this point, we can assert that if a.1 (end) >= b.1
    // (beginning), the times overlap.
    !timespans
        .iter()
        .tuple_windows()
        .any(|(a, b)| a.0 == b.0 || a.1 >= b.0)
}

pub fn check_timespan_duration(times: Vec<u16>, duration: usize) -> Vec<MeetingTimeslot> {
    let duration = duration as u16;
    times_as_timechunks(times)
        .into_par_iter()
        .filter(|t| t.length >= duration)
        .collect()
}

fn times_as_timechunks(times: Vec<u16>) -> Vec<MeetingTimeslot> {
    // We use a BinayHeap to process each element **AS** it is sorted. This should be more
    // efficient than creating a Vec from the elements, and then iterating the vec. No additional
    // allocations.
    let mut timeslots = Vec::with_capacity(times.len());
    let mut sort_heap = BinaryHeap::from(times);
    let mut last_val = None;
    let mut count = 0;

    while let Some(v) = sort_heap.pop() {
        if let Some(last) = last_val {
            if last == v + 1 {
                count += 1;
                last_val = Some(v);
            } else {
                timeslots.push(MeetingTimeslot {
                    start: last,
                    length: count + 1,
                });

                count = 0;
                last_val = Some(v);
            }
        } else {
            // no last value
            last_val = Some(v);
        }
    }

    if let Some(last) = last_val {
        timeslots.push(MeetingTimeslot {
            start: last,
            length: count + 1,
        });
    }

    timeslots
}
