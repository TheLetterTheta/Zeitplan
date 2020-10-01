// Styles
require('./assets/styles/main.scss');

// Polyfills
import 'array-flat-polyfill';

// Fullcalendar
import {
	Calendar,
	EventSource
} from '@fullcalendar/core';
// import bootstrapPlugin from '@fullcalendar/bootstrap';
import interactionPlugin from '@fullcalendar/interaction';
import timeGridPlugin from '@fullcalendar/timegrid';

// localforage
const localforage = require('localforage');

// Dayjs
import dayjs from 'dayjs'

// Tauri
import {
	promisified
} from 'tauri/api/tauri';
var weekOfYear = require('dayjs/plugin/weekOfYear');
dayjs.extend(weekOfYear);

localforage.config({
	driver: localforage.INDEXEDDB, // Force WebSQL; same as using setDriver()
	name: 'zeitplan',
	version: 1.0,
	size: 4980736, // Size of database, in bytes. WebSQL-only for now.
	storeName: 'zeitplan_key_value_pairs', // Should be alphanumeric, with underscores.
	description: 'storage used for users, meetings, and events'
});

// Vendor JS is imported as an entry in webpack.config.js

// Elm
var Elm = require('./elm/Main.elm').Elm;
const app = Elm.Main.init({});
const SELECTED_USER_CALENDAR_ID = 'SELECTED_USER_CALENDAR_ID';

let selectedUserID;
let selectedUserEventSource;
let selectedUserEvents;
const participantCalendarEl = document.getElementById('participant-calendar');
let participantCalendar;

const FINAL_CALENDAR_ID = 'FINAL_CALENDAR_ID';
let finalCalendarEvents;
const finalCalendarEl = document.getElementById('final-calendar');
let finalCalendar;

app.ports.destroyCalendar.subscribe(function() {
	participantCalendar.destroy();
});

app.ports.deleteUser.subscribe(function(u) {
	localforage.removeItem(`${u.id}-events`, () => {});
});

app.ports.saveMeetings.subscribe(function(m) {
	localforage.setItem('meetings', m);
});

app.ports.saveUsers.subscribe(function(users) {
	localforage.setItem('users', users);
});

app.ports.getMeetingTimes.subscribe(async function(meetings){
	if (meetings.length == 0) {
		return;
	}
	let newTimes = await getMeetingAvailability(meetings);

	newTimes = newTimes
		.reduce(function(map, obj) {
			map[obj.id] = obj.timeslots
				.map(t => ({
					ord: t.start,
					time: timeToReadableTime(t)
				}));
			return map;
		}, {});
	app.ports.saveMeetingTimeslots.send(newTimes);
});


app.ports.processWithTauri.subscribe(async function(meetings) {
	if (meetings.length == 0) {
		return;
	}

	const payload = await processMeetingUsers(meetings)

	let start = new Date();
	promisified({
			cmd: 'computeScheduleFromMeetings',
			payload: payload
		})
		.then(r => {
			r = r
			.map(v => {
				v.ord = v.times[0] || 0;
				const len = 1 + v.times.pop() - v.ord;
				v.time = timeToReadableTime({
					start: v.ord,
					length: len
				});
				return v;
			})
			.reduce(function(map, obj) {
				map[obj.id] = { ord: obj.ord, status: obj.status, time: obj.time};
				return map;
			}, {});

			localforage.setItem('computedSchedule', r);
			app.ports.renderComputedSchedule.send(r);
		})
		.catch(e => console.error(e));

});

app.ports.processAllWithTauri.subscribe(async function(meetings) {
	if (meetings.length == 0) {
		return;
	}

	const payload = await processMeetingUsers(meetings)

	let start = new Date();
	promisified({
			cmd: 'computeAllMeetingCombinations',
			payload: payload
		})
		.then(r => {
			r = r
			.map(v => {
				const len = v[1][1] - v[1][0] + 1;
				const r = {};
				r.id = v[0];
				r.ord = v[1][0];
				r.time = timeToReadableTime({
					start: v[1][0],
					length: len
				});
				return r;
			})
			.reduce(function(map, obj) {
				map[obj.id] = { ord: obj.ord, status: "Scheduled", time: obj.time};
				return map;
			}, {});
		
			localforage.setItem('computedSchedule', r);
			app.ports.renderComputedSchedule.send(r);
		})
		.catch(e => console.error(e));

});

function timeToReadableTime(t) {
	const start = dayjs('2020-03-01').add(t.start * 30, 'minute');
	const end = start.add(t.length * 30, 'minute');
	
	if (start.isSame(end, 'day')) {
		let format;
		if (isSameMeridian(start, end)) {
			format = 'dddd [from] h:mm';
		} else {
			format = 'dddd [from] h:mm A';
		}
		const formatTimeOnly = 'h:mm A';
		return `${start.format(format)} – ${end.format(formatTimeOnly)}`;
	}

	const format = 'dddd [at] h:mm A';
	return `${start.format(format)}-${end.format(format)}`;
}

function isSameMeridian(start, end) {
	return (start.get('hour') - 11.5) * (end.get('hour') - 11.5) > 0;
}

async function getMeetingAvailability(meetings) {
	const payload = await processMeetingUsers(meetings);

	let start = new Date();
	try {
		return await promisified({
			cmd: 'computeMeetingSpace',
			payload: payload
		})
	} catch (e) {
		console.error(e);
		return [];
	}
}

async function processMeetingUsers(meetings) {

	let userSet = new Set(meetings.flatMap(m => m.participantIds));
	meetings.forEach((m) => m.duration = m.duration / 30);
	let userMap = [];
	for (let id of userSet) {
		const userEvents = await localforage.getItem(`${id}-events`)
			.then(d => {
				if (d && d instanceof Map) {
					return mapEventsToSlotIndexArray(d);
				} else {
					return []
				}
			});
		userMap.push({
			id,
			events: userEvents
		});
	}

	let availableTimeRange = await localforage.getItem('final-calendar')
		.then((d) => {
			if (d && d instanceof Map) {
				return mapEventsToSlotIndexArray(d);
			} else {
				return []
			}
		});

	return {
		users: userMap,
		meetings: meetings,
		availableTimeRange: availableTimeRange
	}
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
		end.diff(start, 'm') / 30,
		(start.day() * 48) + (start.hour() * 2) + start.minute() / 30
	);
}

function range(size, startAt = 0) {
	return [...Array(size).keys()].map(i => i + startAt);
}

localforage.getItem('meetings')
	.then(meetings => {
		if (meetings && Array.isArray(meetings)) {
			app.ports.loadMeetings.send(meetings);
		}
	});

localforage.getItem('users')
	.then(users => {
		if (users && Array.isArray(users)) {
			app.ports.loadUsers.send(users);
		}
	});

localforage.getItem('computedSchedule')
	.then(schedule => app.ports.renderComputedSchedule.send(schedule));

app.ports.loadUserWithEvents.subscribe(function(newUser) {
	participantCalendarEl.classList.add('blur');


	selectedUserID = newUser.id;
	selectedUserEventSource.refetch();
	participantCalendarEl.classList.remove('blur');
	participantCalendar.render();

});

function saveDate(d) {
	return {
		id: d.id,
		start: d.start,
		end: d.end,
		allDay: d.allDay
	};
}

function loadUserEvents() {
	return new Promise((resolve, reject) => {
		localforage.getItem(`${selectedUserID}-events`)
			.then(function(results) {
				if (results && results instanceof Map) {
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
	})
}

function loadFinalCalendarEvents() {
	return new Promise((resolve, reject) => {
		localforage.getItem("final-calendar")
			.then(function(results) {
				if (results && results instanceof Map) {
					finalCalendarEvents = results;
					app.ports.updateMainCalendar.send(null);
					resolve(Array.from(results.values()));
				} else {
					finalCalendarEvents = new Map();
					reject(new Error("Invalid Database State"))
				}
			})
			.catch(function(e) {
				selectedUserEvents = new Map();
				reject(e);
			});
	});
}


document.addEventListener('DOMContentLoaded', function() {
	participantCalendar = new Calendar(participantCalendarEl, {
		plugins: [
			timeGridPlugin,
			// bootstrapPlugin,
			interactionPlugin
		],
		initialDate: '2020-03-01',
		editable: true,
		unselectAuto: false,
		eventContent: function(e) {
			return eventInnerHtml(e, 'text-dark', function() {
				selectedUserEvents.delete(e.event.id);
				localforage.setItem(`${selectedUserID}-events`, selectedUserEvents)
					.then(_ => app.ports.updateUser.send(selectedUserID));
				e.event.remove()
			})
		},
		selectable: true,
		selectMirror: true,
		navLinks: false,
		eventChange: function(d) {
			selectedUserEvents.set(d.event.id, saveDate(d.event));
			localforage.setItem(`${selectedUserID}-events`, selectedUserEvents)
					.then(_ => app.ports.updateUser.send(selectedUserID));
		},
		select: function(d) {
			d.id = dayjs().unix().toString();

			participantCalendar.addEvent(d, selectedUserEventSource);
			selectedUserEvents.set(d.id, saveDate(d));
			localforage.setItem(`${selectedUserID}-events`, selectedUserEvents)
					.then(_ => app.ports.updateUser.send(selectedUserID));
		},
		selectOverlap: false,
		eventOverlap: false,
		// themeSystem: 'bootstrap',
		eventBackgroundColor: 'var(--info-less-opaque)',
		eventBorderColor: 'white',
		selectMirror: false,
		headerToolbar: false,
		eventSources: [{
			events: function(fetchInfo, successCallback, failureCallback) {
				loadUserEvents()
					.then(d =>
						successCallback(d))
					.catch(_ => successCallback([]));
			},
			id: SELECTED_USER_CALENDAR_ID
		}],
		dayHeaderFormat: {
			'weekday': 'short'
		},
		initialView: 'timeGridWeek',
		allDaySlot: true
	});

	selectedUserEventSource = participantCalendar.getEventSourceById(SELECTED_USER_CALENDAR_ID);

	finalCalendar = new Calendar(finalCalendarEl, {
		plugins: [
			timeGridPlugin,
			// bootstrapPlugin,
			interactionPlugin
		],
		initialDate: '2020-03-01',
		editable: true,
		unselectAuto: false,
		eventContent: function(e) {
			return eventInnerHtml(e, 'text-white', function() {
				finalCalendarEvents.delete(e.event.id);
				localforage.setItem("final-calendar", finalCalendarEvents)
					.then(_ => app.ports.updateMainCalendar.send(null));
				e.event.remove()
			});
		},
		selectable: true,
		selectMirror: true,
		navLinks: false,
		eventChange: function(d) {
			finalCalendarEvents.set(d.event.id, saveDate(d.event));
			localforage.setItem("final-calendar", finalCalendarEvents)
					.then(_ => app.ports.updateMainCalendar.send(null));
		},
		select: function(d) {
			d.id = dayjs().unix().toString();

			finalCalendar.addEvent(d, selectedUserEventSource);
			finalCalendarEvents.set(d.id, saveDate(d));
			localforage.setItem("final-calendar", finalCalendarEvents)
					.then(_ => app.ports.updateMainCalendar.send(null));
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
					.then(d =>
						successCallback(d))
					.catch(_ => successCallback([]));
			},
			id: SELECTED_USER_CALENDAR_ID
		}],
		dayHeaderFormat: {
			'weekday': 'short'
		},
		initialView: 'timeGridWeek',
		allDaySlot: true
	});
	finalCalendar.render();
});

function eventInnerHtml(e, textClass, deleteCallback) {
	let container = document.createElement('div');
	container.classList.add('d-flex', 'align-items-center', 'flex-wrap', 'justify-content-between', 'p-0', 'flex-fill', textClass);

	let deleteButton = document.createElement('button');
	deleteButton.type = "button";
	deleteButton.ariaLabel = "Close";
	deleteButton.classList.add('close');

	let deleteText = document.createElement('span');
	deleteText.innerHTML = '&times;';
	deleteText.ariaHidden = true;
	deleteButton.appendChild(deleteText);

	deleteButton.onclick = deleteCallback;
	let timeText = document.createElement('p');
	timeText.classList.add('m-0');

	if (e.event.allDay) {
		const start = dayjs(e.event.start);
		const end = dayjs(e.event.end);

		timeText.classList.add('fc-event-title');
		let innerText = start.format('ddd');

		if (!start.add(1, 'day').isSame(end, 'day')) {
			innerText += '-' + end.subtract(1, 'day').format('ddd')
		}

		timeText.appendChild(document.createTextNode(innerText));
	} else {
		timeText.classList.add('fc-event-time');
		timeText.appendChild(document.createTextNode(e.timeText));
	}

	container.appendChild(timeText);
	container.appendChild(deleteButton)

	return {
		domNodes: [container]
	};
}
