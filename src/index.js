// Styles
require('./assets/styles/main.scss');

// Fullcalendar
import { Calendar, EventSource } from '@fullcalendar/core';
// import bootstrapPlugin from '@fullcalendar/bootstrap';
import interactionPlugin from '@fullcalendar/interaction';
import timeGridPlugin from '@fullcalendar/timegrid';
import localforage from 'localforage';
import dayjs from 'dayjs'
// import { promisified } from 'tauri/api/tauri';
var weekOfYear = require('dayjs/plugin/weekOfYear');
dayjs.extend(weekOfYear);

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
let finalCalendarEventSource;
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


app.ports.processWithTauri.subscribe(async function({users, meetings}) {
	console.log({users, meetings});

	users = new Set(meetings.flatMap(m => m.participantIds));
	let userMap = new Map();
	for (let id of users) {
		const userEvents = await localforage.getItem(`${id}-events`)
			.then(d => {
				if (d && d instanceof Map) {
					return Array.from(d.values())
				} else {
					return []
				}
			});
		userMap.set(id, userEvents);
	}
	// promisified({
	// 	cmd: 'test',
	// 	data: true
	// })
	// 	.then(r => console.log(r))
	// 	.catch(e => console.error(e));

});

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

app.ports.loadUserWithEvents.subscribe(function(newUser) {
	participantCalendarEl.classList.add('blur');


	selectedUserID = newUser.id;
	selectedUserEventSource.refetch();
	participantCalendarEl.classList.remove('blur');
	participantCalendar.render();

});

function saveDate(d) {
	return { id: d.id, start: d.start, end: d.end, allDay: d.allDay };
}

function loadUserEvents() {
	return new Promise((resolve, reject) => {
		localforage.getItem(`${selectedUserID}-events`)
		.then(function(results) {
			if (results && results instanceof Map) {
				selectedUserEvents = results;
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
				if (results && results instanceof Map){
					finalCalendarEvents = results;
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
				localforage.setItem(`${selectedUserID}-events`, selectedUserEvents);
				e.event.remove()
			})
		},
		selectable: true,
		selectMirror: true,
		navLinks: false,
		eventChange: function(d) {
			selectedUserEvents.set(d.event.id, saveDate(d.event));
			localforage.setItem(`${selectedUserID}-events`, selectedUserEvents);
		},
		select: function(d) {
			d.id = dayjs().unix().toString();

			participantCalendar.addEvent(d, selectedUserEventSource);
			selectedUserEvents.set(d.id,saveDate(d));
			localforage.setItem(`${selectedUserID}-events`, selectedUserEvents);
		},
		selectOverlap: false,
		eventOverlap: false,
		// themeSystem: 'bootstrap',
		eventBackgroundColor: 'var(--info)',
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
				localforage.setItem("final-calendar", finalCalendarEvents);
				e.event.remove()
			});
		},
		selectable: true,
		selectMirror: true,
		navLinks: false,
		eventChange: function(d) {
			finalCalendarEvents.set(d.event.id, saveDate(d.event));
			localforage.setItem("final-calendar", finalCalendarEvents);
		},
		select: function(d) {
			d.id = dayjs().unix().toString();

			finalCalendar.addEvent(d, selectedUserEventSource);
			finalCalendarEvents.set(d.id,saveDate(d));
			localforage.setItem("final-calendar", finalCalendarEvents);
		},
		selectOverlap: false,
		eventOverlap: false,
		// themeSystem: 'bootstrap',
		eventBackgroundColor: "var(--dark)",
		eventBorderColor: "var(--primary)",
		selectMirror: false,
		headerToolbar: false,
		eventSources: [
			{
				events: function(fetchInfo, successCallback, failureCallback) {
					loadFinalCalendarEvents()
					.then(d =>
						successCallback(d))
					.catch(_ => successCallback([]));
				},
				id: SELECTED_USER_CALENDAR_ID
			}
		],
		dayHeaderFormat: {
			'weekday': 'short'
		},
		initialView: 'timeGridWeek',
		allDaySlot: true
	});

	finalCalendarEventSource = finalCalendar.getEventSourceById(FINAL_CALENDAR_ID);
	finalCalendar.render();
});

function eventInnerHtml(e, textClass, deleteCallback){
	let container = document.createElement('div');
	container.classList.add('d-flex','align-items-center', 'flex-wrap', 'justify-content-between', 'p-0', 'flex-fill', textClass);

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

		if (! start.add(1, 'day').isSame(end, 'day') ) {
			innerText += '-'  + end.subtract(1, 'day').format('ddd')
		}

		timeText.appendChild(document.createTextNode(innerText));
	} else {
		timeText.classList.add('fc-event-time');
		timeText.appendChild(document.createTextNode(e.timeText));
	}

	container.appendChild(timeText);
	container.appendChild(deleteButton)
	return { domNodes: [ container ] };
}
