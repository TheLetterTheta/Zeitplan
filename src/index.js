// Styles
require("./assets/styles/main.scss");

// Polyfills
import "array-flat-polyfill";

// Fullcalendar
import {
  Calendar,
  EventSource
} from "@fullcalendar/core";
// import bootstrapPlugin from '@fullcalendar/bootstrap';
import interactionPlugin from "@fullcalendar/interaction";
import timeGridPlugin from "@fullcalendar/timegrid";

import {
  setKey,
  getKey,
  deleteKey
} from "./storage";

// Dayjs
import dayjs from "dayjs";

// Tauri
import {
  promisified
} from "tauri/api/tauri";
var weekOfYear = require("dayjs/plugin/weekOfYear");
dayjs.extend(weekOfYear);

// Vendor JS is imported as an entry in webpack.config.js

// Elm
var Elm = require("./elm/Main.elm").Elm;
const app = Elm.Main.init({});
const SELECTED_USER_CALENDAR_ID = "SELECTED_USER_CALENDAR_ID";

let selectedUserID;
let selectedUserEventSource;
let selectedUserEvents;
const participantCalendarEl = document.getElementById("participant-calendar");
let participantCalendar;

const FINAL_CALENDAR_ID = "FINAL_CALENDAR_ID";
let finalCalendarEvents;
const finalCalendarEl = document.getElementById("final-calendar");
let finalCalendar;

app.ports.destroyCalendar.subscribe(function() {
  participantCalendar.destroy();
});

app.ports.deleteUser.subscribe(function(u) {
  deleteKey(`${u.id}-events`);
});

app.ports.saveMeetings.subscribe(function(m) {
  setKey("meetings", m);
});

app.ports.saveUsers.subscribe(function(users) {
  setKey("users", users);
});

app.ports.getMeetingTimes.subscribe(async function(meetings) {
  if (meetings.length == 0) {
    return;
  }
  let newTimes = await getMeetingAvailability(meetings);

  newTimes = newTimes.reduce(function(map, obj) {
    map[obj.id] = obj.timeslots.map((t) => ({
      ord: t.start,
      time: timeToReadableTime(t),
    }));
    return map;
  }, {});
  app.ports.saveMeetingTimeslots.send(newTimes);
});

app.ports.processWithTauri.subscribe(async function([meetings, lockedEvents]) {
  if (meetings.length == 0) {
    return;
  }

  const payload = await processMeetingUsers(meetings, lockedEvents);

  let start = new Date();
  let event;

  if (window.__TAURI__) {
    event = promisified({
      cmd: "computeScheduleFromMeetings",
      payload: payload,
    });
  } else {
    // TODO: Call the API!!!
    event = Promise.resolve();
  }

  event
    .then((r) => {
      r = {
        status: "Success",
        data: r
          .map((v) => {
            v.slots = [...v.times];
            v.ord = v.times[0] || -1;
            const len = 1 + v.times.pop() - v.ord;
            v.time = timeToReadableTime({
              start: v.ord,
              length: len,
            });
            return v;
          })
          .reduce(function(map, obj) {
            map[obj.id] = {
              ord: obj.ord,
              status: obj.status,
              time: obj.time,
              slots: obj.slots,
            };
            return map;
          }, {}),
      };

      lockedEvents.forEach((e) => (r.data[e[0]] = e[1]));

      setKey("computedSchedule", r);
      app.ports.renderComputedSchedule.send(r);
    })
    .catch((e) => console.error(e));
});

app.ports.processAllWithTauri.subscribe(async function([
  meetings,
  lockedEvents,
]) {
  if (meetings.length == 0) {
    return;
  }

  const payload = await processMeetingUsers(meetings, lockedEvents);

  let start = new Date();
  let event;
  if (window.__TAURI__) {
    event = promisified({
      cmd: "computeAllMeetingCombinations",
      payload: payload,
    });
  } else {
    // TODO: Call the API!!!
    event = Promise.resolve();
  }

  event
    .then((r) => {
      if (!r) {
        r = {
          status: "Fail",
        };
      } else {
        r = {
          status: "Success",
          data: r
            .map((v) => {
              const len = v[1][1] - v[1][0] + 1;
              const r = {};
              r.id = v[0];
              r.ord = v[1][0];
              r.slots = range(len, v[1][0]);
              r.time = timeToReadableTime({
                start: v[1][0],
                length: len,
              });

              return r;
            })
            .reduce(function(map, obj) {
              map[obj.id] = {
                ord: obj.ord,
                status: "Scheduled",
                time: obj.time,
                slots: obj.slots,
              };
              return map;
            }, {}),
        };
      }

      lockedEvents.forEach((e) => (r.data[e[0]] = e[1]));

      setKey("computedSchedule", r);
      app.ports.renderComputedSchedule.send(r);
    })
    .catch((e) => console.error(e));
});

function timeToReadableTime(t) {
  const start = dayjs("2020-03-01").add(t.start * 30, "minute");
  const end = start.add(t.length * 30, "minute");

  if (start.isSame(end, "day")) {
    let format;
    if (isSameMeridian(start, end)) {
      format = "dddd [from] h:mm";
    } else {
      format = "dddd [from] h:mm A";
    }
    const formatTimeOnly = "h:mm A";
    return `${start.format(format)} – ${end.format(formatTimeOnly)}`;
  }

  const format = "dddd [at] h:mm A";
  return `${start.format(format)}-${end.format(format)}`;
}

function isSameMeridian(start, end) {
  return (start.get("hour") - 11.5) * (end.get("hour") - 11.5) > 0;
}

async function getMeetingAvailability(meetings) {
  const payload = await processMeetingUsers(meetings);

  let start = new Date();
  try {
    let event;
    if (window.__TAURI__) {
      return await promisified({
        cmd: "computeMeetingSpace",
        payload: payload,
      });
    } else {
      // TODO: Call the api!!!
    }
  } catch (e) {
    console.error(e);
    return [];
  }
}

function toMap(data) {
  let ret = new Map();
  for (let [key, value] of Object.entries(data)) {
    ret.set(key, value);
  }
  return ret;
}

function numerically(a, b) {
  return a - b;
}

async function processMeetingUsers(meetings, lockedSchedule = []) {
  let userSet = new Set(meetings.flatMap((m) => m.participantIds));

  meetings = meetings.filter(
    (meeting) => !lockedSchedule.some((l) => l[0] == meeting.id)
  );
  meetings.forEach((m) => (m.duration = m.duration / 30));

  let userMap = [];
  for (let id of userSet) {
    const userEvents = await getKey(`${id}-events`).then((d) => {
      if (d) {
        if (!(d instanceof Map)) {
          d = toMap(d);
        }
        return mapEventsToSlotIndexArray(d);
      } else {
        return [];
      }
    });
    userMap.push({
      id,
      events: userEvents,
    });
  }

  let lockedTimes = lockedSchedule.flatMap((s) => s[1].slots);
  lockedTimes.sort(numerically);

  let availableTimeRange = await getKey("final-calendar").then((d) => {
    if (d) {
      if (!(d instanceof Map)) {
        d = toMap(d);
      }
      return mapEventsToSlotIndexArray(d);
    } else {
      return [];
    }
  });

  availableTimeRange.sort(numerically);

  let i = 0,
    j = 0;
  while (i < availableTimeRange.length && j < lockedTimes.length) {
    if (availableTimeRange[i] < lockedTimes[j]) {
      ++i;
    } else if (availableTimeRange[i] === lockedTimes[j]) {
      availableTimeRange.splice(i, 1);
      ++j;
    } else if (availableTimeRange[i] > lockedTimes[j]) {
      ++j;
    }
  }

  return {
    users: userMap,
    meetings: meetings,
    availableTimeRange: availableTimeRange,
  };
}

function mapEventsToSlotIndexArray(events) {
  // We know that the events do not overlap, as defined in our FullCalendar initialization. Therefore, we can push the events to an array in a simple for...of loop
  let eventTimesAsNumbers = [];
  for (const event of events.values()) {
    eventTimesAsNumbers.push(eventToThirtyMinuteSlotIndexArray(event));
  }
  return eventTimesAsNumbers.flat();
}

function eventToThirtyMinuteSlotIndexArray(event) {
  let start = dayjs(event.start);
  let end = dayjs(event.end);

  return range(
    end.diff(start, "m") / 30,
    start.day() * 48 + start.hour() * 2 + start.minute() / 30
  );
}

function range(size, startAt = 0) {
  return [...Array(size).keys()].map((i) => i + startAt);
}

getKey("meetings").then((meetings) => {
  if (meetings && Array.isArray(meetings)) {
    app.ports.loadMeetings.send(meetings);
  }
});

getKey("users").then((users) => {
  if (users && Array.isArray(users)) {
    app.ports.loadUsers.send(users);
  }
});

getKey("computedSchedule").then((schedule) =>
  app.ports.renderComputedSchedule.send(schedule)
);

app.ports.loadUserWithEvents.subscribe(function(newUser) {
  participantCalendarEl.classList.add("blur");

  selectedUserID = newUser.id;
  selectedUserEventSource.refetch();
  participantCalendarEl.classList.remove("blur");
  participantCalendar.render();
});

function saveDate(d) {
  return {
    id: d.id,
    start: d.start,
    end: d.end,
    allDay: d.allDay,
  };
}

function loadUserEvents() {
  return new Promise((resolve, reject) => {
    getKey(`${selectedUserID}-events`)
      .then(function(results) {
        if (results) {
          if (!(results instanceof Map)) {
            results = toMap(results);
          }
          selectedUserEvents = results;
          app.ports.updateUser.send(selectedUserID);
          resolve(Array.from(results.values()));
        } else {
          selectedUserEvents = new Map();
          reject(new Error("Invalid Database State"));
        }
      })
      .catch(function(e) {
        selectedUserEvents = new Map();
        reject(e);
      });
  });
}

function loadFinalCalendarEvents() {
  return new Promise((resolve, reject) => {
    getKey("final-calendar")
      .then(function(results) {
        if (results) {
          if (!(results instanceof Map)) {
            results = toMap(results);
          }

          finalCalendarEvents = results;
          app.ports.updateMainCalendar.send(null);
          resolve(Array.from(results.values()));
        } else if (results === null) {
          finalCalendarEvents = new Map();
          app.ports.updateMainCalendar.send(null);
          resolve([]);
        } else {
          finalCalendarEvents = new Map();
          reject(new Error("Invalid Database State"));
        }
      })
      .catch(function(e) {
        selectedUserEvents = new Map();
        reject(e);
      });
  });
}

document.addEventListener("DOMContentLoaded", function() {
  participantCalendar = new Calendar(participantCalendarEl, {
    plugins: [
      timeGridPlugin,
      // bootstrapPlugin,
      interactionPlugin,
    ],
    initialDate: "2020-03-01",
    editable: true,
    unselectAuto: false,
    eventContent: function(e) {
      return eventInnerHtml(e, "text-dark", function() {
        selectedUserEvents.delete(e.event.id);
        setKey(`${selectedUserID}-events`, selectedUserEvents).then((_) =>
          app.ports.updateUser.send(selectedUserID)
        );
        e.event.remove();
      });
    },
    selectable: true,
    selectMirror: true,
    navLinks: false,
    eventChange: function(d) {
      selectedUserEvents.set(d.event.id, saveDate(d.event));
      setKey(`${selectedUserID}-events`, selectedUserEvents).then((_) =>
        app.ports.updateUser.send(selectedUserID)
      );
    },
    select: function(d) {
      d.id = dayjs().unix().toString();

      participantCalendar.addEvent(d, selectedUserEventSource);
      selectedUserEvents.set(d.id, saveDate(d));
      setKey(`${selectedUserID}-events`, selectedUserEvents).then((_) =>
        app.ports.updateUser.send(selectedUserID)
      );
    },
    selectOverlap: false,
    eventOverlap: false,
    // themeSystem: 'bootstrap',
    eventBackgroundColor: "var(--info-less-opaque)",
    eventBorderColor: "white",
    selectMirror: false,
    headerToolbar: false,
    eventSources: [{
      events: function(fetchInfo, successCallback, failureCallback) {
        loadUserEvents()
          .then((d) => successCallback(d))
          .catch((_) => successCallback([]));
      },
      id: SELECTED_USER_CALENDAR_ID,
    }, ],
    dayHeaderFormat: {
      weekday: "short",
    },
    initialView: "timeGridWeek",
    allDaySlot: true,
  });

  selectedUserEventSource = participantCalendar.getEventSourceById(
    SELECTED_USER_CALENDAR_ID
  );

  finalCalendar = new Calendar(finalCalendarEl, {
    plugins: [
      timeGridPlugin,
      // bootstrapPlugin,
      interactionPlugin,
    ],
    initialDate: "2020-03-01",
    editable: true,
    unselectAuto: false,
    eventContent: function(e) {
      return eventInnerHtml(e, "text-white", function() {
        finalCalendarEvents.delete(e.event.id);
        setKey("final-calendar", finalCalendarEvents).then((_) =>
          app.ports.updateMainCalendar.send(null)
        );
        e.event.remove();
      });
    },
    selectable: true,
    selectMirror: true,
    navLinks: false,
    eventChange: function(d) {
      finalCalendarEvents.set(d.event.id, saveDate(d.event));
      setKey("final-calendar", finalCalendarEvents).then((_) =>
        app.ports.updateMainCalendar.send(null)
      );
    },
    select: function(d) {
      d.id = dayjs().unix().toString();

      finalCalendar.addEvent(d, selectedUserEventSource);
      finalCalendarEvents.set(d.id, saveDate(d));
      setKey("final-calendar", finalCalendarEvents).then((_) =>
        app.ports.updateMainCalendar.send(null)
      );
    },
    selectOverlap: false,
    eventOverlap: false,
    // themeSystem: 'bootstrap',
    eventBackgroundColor: "var(--dark-less-opaque)",
    eventBorderColor: "var(--primary)",
    selectMirror: false,
    headerToolbar: false,
    eventSources: [{
      events: function(fetchInfo, successCallback, failureCallback) {
        loadFinalCalendarEvents()
          .then((d) => successCallback(d))
          .catch((_) => successCallback([]));
      },
      id: SELECTED_USER_CALENDAR_ID,
    }, ],
    dayHeaderFormat: {
      weekday: "short",
    },
    initialView: "timeGridWeek",
    allDaySlot: true,
  });
  finalCalendar.render();
});

function eventInnerHtml(e, textClass, deleteCallback) {
  let container = document.createElement("div");
  container.classList.add(
    "d-flex",
    "align-items-center",
    "flex-wrap",
    "justify-content-between",
    "p-0",
    "flex-fill",
    textClass
  );

  let deleteButton = document.createElement("button");
  deleteButton.type = "button";
  deleteButton.ariaLabel = "Close";
  deleteButton.classList.add("close");

  let deleteText = document.createElement("span");
  deleteText.innerHTML = "&times;";
  deleteText.ariaHidden = true;
  deleteButton.appendChild(deleteText);

  deleteButton.onclick = deleteCallback;
  let timeText = document.createElement("p");
  timeText.classList.add("m-0");

  if (e.event.allDay) {
    const start = dayjs(e.event.start);
    const end = dayjs(e.event.end);

    timeText.classList.add("fc-event-title");
    let innerText = start.format("ddd");

    if (!start.add(1, "day").isSame(end, "day")) {
      innerText += "-" + end.subtract(1, "day").format("ddd");
    }

    timeText.appendChild(document.createTextNode(innerText));
  } else {
    timeText.classList.add("fc-event-time");
    timeText.appendChild(document.createTextNode(e.timeText));
  }

  container.appendChild(timeText);
  container.appendChild(deleteButton);

  return {
    domNodes: [container],
  };
}
