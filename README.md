# Zeitplan

# Info

Zeitplan is a scheduling application with a very specific use case.
It comprises of 3 individual steps:

1. Setup Participants

- Add others who will be participaing in these meetings.
- If they have any times they **CANNOT** meet, denote that in the designated calendar area.

2. Setup Meetings

- Choose meeting participants _(there can be multiple participants in each meeting)_
- Give it a name, and a duration _(currently only in steps of 30 minutes, up to 120 minutes)_
- View meetings. This area also includes information about the meetings being scheduled (When the possible meeting times **can** be scheduled)

3. Final Calendar

- Denote the times which you would like to schedule the meetings.
- Move times around, and see the updates to the meetings in the area above
- SCHEDULE

4. Schedule

- Run the scheduler to compute a possible solution. The initial run doesn't **guarantee** to find the solution if it exists
- Optionally: Rerun the scheduler with the checkbox to exhaustively check every possible configuration.

# How

## Elm

The UI is built in elm, with help from Bootstrap, Fullcalendar, FontAwesome, and javascript.

## Tauri

The complex calucations are done in Rust with help from Tauri (for speed). The application is built with Tauri, and shipped with it as well. I want to give a huge thanks to the awesome work they're doing over on that project!

# Build

You will need Elm, Node, and Rust installed to build the project. Also, follow the Getting Started guide over at the Tauri project specific to your platform for compiling and bundling.

## Development

For development, run 2 processes `yarn dev` to start the Elm server, and `yarn tauri dev` to host a local instance of a Tauri window to run Rust commands through.

## Production

To build the Elm project, run `yarn prod` **NOT `yarn prod:compress` (Tauri doesn't seem to work well with gzipped files at the moment)**. This generates files into the `dist/` folder.
Then run `yarn tauri build` to comiple all rust dependencies, and bundle the app specific to your platform. This looks at files in the `dist/` folder, and generates a new `dist/index.tauri.html` file.
