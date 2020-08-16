// Styles
require('./assets/styles/main.scss');

import localforage from 'localforage';

// Vendor JS is imported as an entry in webpack.config.js

// Elm
var Elm = require('./elm/Main.elm').Elm;
const app = Elm.Main.init({});


app.ports.saveUsers.subscribe(function(users) {
	localforage.setItem('users', users);
});

localforage.getItem('users')
	.then(users => {
		if (users) {
			app.ports.loadUsers.send(users);
		}
	});

import { Calendar } from '@fullcalendar/core';
import timeGridPlugin from '@fullcalendar/timegrid';
import bootstrapPlugin from '@fullcalendar/bootstrap';
import interactionPlugin from '@fullcalendar/interaction';

document.addEventListener('DOMContentLoaded', function () {
	var calendarEl = document.getElementById('calendar');

	var calendar = new Calendar(calendarEl, {
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

	calendar.render();
});
