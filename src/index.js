// Styles
require('./assets/styles/main.scss');

// Fullcalendar
import { Calendar } from '@fullcalendar/core';
import bootstrapPlugin from '@fullcalendar/bootstrap';
import interactionPlugin from '@fullcalendar/interaction';
import timeGridPlugin from '@fullcalendar/timegrid';
import localforage from 'localforage';

// Vendor JS is imported as an entry in webpack.config.js

// Elm
var Elm = require('./elm/Main.elm').Elm;
const app = Elm.Main.init({});

app.ports.destroyCalendar.subscribe(function() {
	calendar.destroy();
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
	calendarEl.classList.add('blur');

	localforage.getItem(`${newUser.id}-events`)
		.then(function(results) {
			if (results && Array.isArray(results)) {
				calendar.events = results;
			}
		})
		.finally(function() {
			calendarEl.classList.remove('blur');
			calendar.render();
		});

});

const calendarEl = document.getElementById('calendar');
let calendar;

document.addEventListener('DOMContentLoaded', function() {
	calendar = new Calendar(calendarEl, {
		plugins: [
			timeGridPlugin,
			bootstrapPlugin,
			interactionPlugin
		],
		editable: true,
		selectable: true,
		themeSystem: 'bootstratp',
		headerToolbar: false,
		dayHeaderFormat: {
			'weekday': 'short'
		},
		initialView: 'timeGridWeek',
		allDaySlot: false
	});
});
