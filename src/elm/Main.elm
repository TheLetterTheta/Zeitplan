port module Main exposing (main)

import Animation exposing (percent, px, rad)
import Animation.Spring.Presets exposing (stiff)
import Browser exposing (Document)
import Browser.Dom as Dom
import Debug
import Dict
import FontAwesome.Icon as Icon exposing (Icon)
import FontAwesome.Solid as Icon
import FontAwesome.Styles as Icon
import Html exposing (Html, blockquote, br, button, div, footer, form, h1, h3, h5, h6, i, input, label, li, mark, nav, p, span, strong, text, ul)
import Html.Attributes as Attributes exposing (attribute, class, for, id, max, min, name, required, step, style, type_, value)
import Html.Events exposing (onClick, onInput)
import Html.Keyed
import Html.Lazy exposing (lazy)
import Json.Decode as Decode exposing (Decoder, Value, decodeValue, int, list, string)
import Json.Decode.Pipeline as Pipeline exposing (required)
import Task as Task exposing (perform)
import Time as Time exposing (Posix)



-- MODEL


type alias User =
    { id : String
    , name : String
    }


type alias Meeting =
    { id : String
    , title : String
    , participantIds : List String
    , duration : Int
    , expandTimeslots : Bool
    }


type alias MeetingTimeslot =
    { ord : Int
    , time : String
    }


initialDropdownStyle =
    Animation.style
        [ Animation.display Animation.none
        , Animation.opacity 0
        ]


dropdownShownAnimation =
    Animation.interrupt
        [ Animation.set [ Animation.display Animation.block ]
        , Animation.to [ Animation.opacity 1 ]
        ]


dropdownHiddenAnimation =
    Animation.interrupt
        [ Animation.to [ Animation.opacity 0 ]
        , Animation.set [ Animation.display Animation.none ]
        ]


initialChevronStyle =
    Animation.styleWith (Animation.speed { perSecond = 20 })
        [ Animation.rotate (rad 0) ]


rotatePi =
    Animation.interrupt [ Animation.to [ Animation.rotate (rad -pi) ] ]


rotateStart =
    Animation.interrupt [ Animation.to [ Animation.rotate (rad 0) ] ]


type alias ResultStatus =
    { status : String
    , time : String
    , ord : Int
    }


type alias Model =
    { participants : List User
    , selectedUser : Maybe User
    , newUserName : String
    , isExpandToggleNewUserForm : Bool
    , isExpandParticipants : Bool
    , isExpandMeetings : Bool
    , meetingParticipants : List User
    , meetingDuration : Int
    , meetingTitle : String
    , meetingTimes : Dict.Dict String (List MeetingTimeslot)
    , meetings : List Meeting
    , userDropdownStyle : Animation.State
    , meetingDropdownStyle : Animation.State
    , participantsChevronAnimationStyle : Animation.State
    , meetingChevronAnimationStyle : Animation.State
    , newUserAnimationStyle : Animation.State
    , results : Dict.Dict String ResultStatus
    }


init : ( Model, Cmd Msg )
init =
    ( { isExpandToggleNewUserForm = False
      , participants = []
      , selectedUser = Nothing
      , meetings = []
      , newUserName = ""
      , isExpandParticipants = False
      , isExpandMeetings = False
      , meetingParticipants = []
      , meetingDuration = 60
      , meetingTitle = ""
      , userDropdownStyle = initialDropdownStyle
      , meetingDropdownStyle = initialDropdownStyle
      , participantsChevronAnimationStyle = initialChevronStyle
      , meetingChevronAnimationStyle = initialChevronStyle
      , newUserAnimationStyle = initialDropdownStyle
      , results = Dict.empty
      , meetingTimes = Dict.empty
      }
    , Cmd.none
    )



-- UPDATE


type Msg
    = SelectUser User
    | ToggleNewUserForm
    | UpdateUserName String
    | DeleteMeeting Meeting
    | SaveUser
    | SaveUserWithId Time.Posix
    | ToggleExpandParticipants
    | ToggleExpandMeetings
    | ToggleUserMeeting User
    | ToggleExpandMeetingTime Meeting
    | LoadUsers Decode.Value
    | LoadMeetings Decode.Value
    | DeleteUser User
    | AddMeeting
    | SetMeetingLength Int
    | RunScheduler
    | Animate Animation.Msg
    | SetMeetingTitle String
    | SaveMeetingWithId Time.Posix
    | SaveMeetingAvailableTimeslots Decode.Value
    | DisplayComputedSchedule Decode.Value
    | RefreshMeetingsWithUserId Decode.Value
    | RefreshAllMeetings ()
    | NoOp


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        RunScheduler ->
            ( model, processWithTauri model.meetings )

        LoadMeetings jsValue ->
            case decodeValue decodeMeetings jsValue of
                Ok data ->
                    ( { model | meetings = data }, getMeetingTimes data )

                Err error ->
                    ( model, Cmd.none )

        AddMeeting ->
            ( model, Task.perform SaveMeetingWithId Time.now )

        SaveMeetingWithId currentTimestamp ->
            let
                newMeeting : Meeting
                newMeeting =
                    { id =
                        String.fromInt <|
                            Time.posixToMillis currentTimestamp
                    , title = model.meetingTitle
                    , participantIds = List.map (\u -> u.id) model.meetingParticipants
                    , duration = model.meetingDuration
                    , expandTimeslots = False
                    }

                newMeetings =
                    newMeeting :: model.meetings
            in
            ( { model
                | meetingParticipants = []
                , meetings = newMeetings
              }
            , Cmd.batch
                [ saveMeetings newMeetings
                , getMeetingTimes [ newMeeting ]
                ]
            )

        SaveMeetingAvailableTimeslots jsValue ->
            case decodeValue decodeTimeslots jsValue of
                Ok data ->
                    ( { model | meetingTimes = Dict.union data model.meetingTimes }, Cmd.none )

                Err error ->
                    ( model, Cmd.none )

        DisplayComputedSchedule jsValue ->
            case decodeValue decodeResults jsValue of
                Ok data ->
                    ( { model | results = data }, Cmd.none )

                Err _ ->
                    ( { model | results = Dict.empty }, Cmd.none )

        RefreshMeetingsWithUserId jsValue ->
            case decodeValue Decode.string jsValue of
                Ok userId ->
                    let
                        affectedMeetings =
                            model.meetings
                                |> List.filter (\m -> List.member userId m.participantIds)
                    in
                    ( model, getMeetingTimes affectedMeetings )

                Err _ ->
                    ( model, Cmd.none )

        RefreshAllMeetings _ ->
            ( model, getMeetingTimes model.meetings )

        DeleteMeeting meeting ->
            let
                newMeetings =
                    List.filter (\m -> m /= meeting) model.meetings
            in
            ( { model | meetings = newMeetings }
            , saveMeetings newMeetings
            )

        SetMeetingTitle s ->
            ( { model | meetingTitle = s }, Cmd.none )

        SetMeetingLength l ->
            ( { model | meetingDuration = l }, Cmd.none )

        LoadUsers jsValue ->
            case decodeValue decodeUsers jsValue of
                Ok data ->
                    ( { model | participants = data }, Cmd.none )

                Err error ->
                    ( model, Cmd.none )

        UpdateUserName name ->
            ( { model | newUserName = name }, Cmd.none )

        SaveUser ->
            ( model, Task.perform SaveUserWithId Time.now )

        SaveUserWithId currentTimestamp ->
            let
                newUser =
                    { id =
                        String.fromInt <|
                            Time.posixToMillis currentTimestamp
                    , name = model.newUserName
                    }

                shouldAdd =
                    String.trim model.newUserName /= ""

                newModel =
                    if shouldAdd then
                        { model
                            | participants = newUser :: model.participants
                            , newUserName = ""
                        }

                    else
                        model
            in
            ( newModel
            , Cmd.batch
                [ focusToggleNewUserFormInput
                , saveUsers newModel.participants
                ]
            )

        SelectUser s ->
            if model.selectedUser == Just s then
                ( model, Cmd.none )

            else
                ( { model | selectedUser = Just s }, loadUserWithEvents s )

        DeleteUser u ->
            let
                filteredUsers =
                    List.filter (\user -> user /= u) model.participants

                filteredMeetingUsers =
                    List.filter (\user -> user /= u) model.meetingParticipants

                ( modifiedMeetings, untouchedMeetings ) =
                    model.meetings
                        |> List.partition (\m -> List.member u.id m.participantIds)

                updatedModifiedMeetings =
                    modifiedMeetings
                        |> List.map (\m -> { m | participantIds = List.filter (\id -> id /= u.id) m.participantIds })
                        |> List.filter (\m -> List.length m.participantIds > 0)

                updatedMeetings =
                    updatedModifiedMeetings ++ untouchedMeetings
            in
            ( { model
                | participants = filteredUsers
                , selectedUser = Nothing
                , meetingParticipants = filteredMeetingUsers
                , meetings = updatedMeetings
              }
            , Cmd.batch
                [ saveUsers filteredUsers
                , deleteUser u
                , destroyCalendar ()
                , getMeetingTimes updatedModifiedMeetings
                , saveMeetings updatedMeetings
                ]
            )

        ToggleUserMeeting u ->
            ( { model
                | meetingParticipants =
                    if List.member u model.meetingParticipants then
                        List.filter (\user -> user /= u) model.meetingParticipants

                    else
                        u :: model.meetingParticipants
              }
            , Cmd.none
            )

        ToggleExpandMeetings ->
            let
                ( dropdownStyle, chevronStyle ) =
                    if model.isExpandMeetings then
                        ( dropdownHiddenAnimation model.meetingDropdownStyle
                        , rotateStart model.meetingChevronAnimationStyle
                        )

                    else
                        ( dropdownShownAnimation model.meetingDropdownStyle
                        , rotatePi model.meetingChevronAnimationStyle
                        )
            in
            ( { model
                | isExpandMeetings = not model.isExpandMeetings
                , meetingDropdownStyle = dropdownStyle
                , meetingChevronAnimationStyle = chevronStyle
              }
            , Cmd.none
            )

        ToggleExpandMeetingTime meeting ->
            let
                updatedMeetings =
                    model.meetings
                        |> List.map
                            (\m ->
                                if meeting == m then
                                    { m | expandTimeslots = not m.expandTimeslots }

                                else
                                    m
                            )
            in
            ( { model
                | meetings = updatedMeetings
              }
            , Cmd.none
            )

        ToggleExpandParticipants ->
            let
                ( dropdownStyle, chevronStyle ) =
                    if model.isExpandParticipants then
                        ( dropdownHiddenAnimation model.userDropdownStyle
                        , rotateStart model.participantsChevronAnimationStyle
                        )

                    else
                        ( dropdownShownAnimation model.userDropdownStyle
                        , rotatePi model.participantsChevronAnimationStyle
                        )
            in
            ( { model
                | userDropdownStyle = dropdownStyle
                , participantsChevronAnimationStyle = chevronStyle
                , isExpandParticipants = not model.isExpandParticipants
              }
            , Cmd.none
            )

        Animate animationMsg ->
            ( { model
                | userDropdownStyle = Animation.update animationMsg model.userDropdownStyle
                , meetingDropdownStyle = Animation.update animationMsg model.meetingDropdownStyle
                , participantsChevronAnimationStyle = Animation.update animationMsg model.participantsChevronAnimationStyle
                , meetingChevronAnimationStyle = Animation.update animationMsg model.meetingChevronAnimationStyle
                , newUserAnimationStyle = Animation.update animationMsg model.newUserAnimationStyle
              }
            , Cmd.none
            )

        ToggleNewUserForm ->
            let
                style =
                    if model.isExpandToggleNewUserForm then
                        dropdownHiddenAnimation model.newUserAnimationStyle

                    else
                        dropdownShownAnimation model.newUserAnimationStyle
            in
            ( { model
                | newUserName = ""
                , isExpandToggleNewUserForm = not model.isExpandToggleNewUserForm
                , newUserAnimationStyle = style
              }
            , Cmd.none
            )



-- TASKS


focusToggleNewUserFormInput : Cmd Msg
focusToggleNewUserFormInput =
    Task.attempt (\_ -> NoOp) (Dom.focus "new-user-name-input")



-- VIEW


renderKeyedUser : Maybe User -> User -> ( String, Html Msg )
renderKeyedUser activeUser user =
    let
        classes =
            "list-group-item list-group-item-action"
                ++ (if Just user == activeUser then
                        " active"

                    else
                        ""
                   )
    in
    ( user.id
    , lazy
        (\u ->
            button
                [ onClick (SelectUser u), class classes ]
                [ text u.name ]
        )
        user
    )


newUserButton : Model -> Html Msg
newUserButton model =
    let
        ( buttonClass, icon, buttonText ) =
            if not model.isExpandToggleNewUserForm then
                ( "btn-success", Icon.userPlus, "Show" )

            else
                ( "btn-danger", Icon.userTimes, "Hide" )

        classList =
            buttonClass ++ " list-group-item list-group-item-action text-center"
    in
    button
        [ class classList
        , onClick ToggleNewUserForm
        ]
        [ Icon.viewIcon icon, p [ class "m-0" ] [ text buttonText ] ]


newUserForm : Model -> Html Msg
newUserForm model =
    div (Animation.render model.newUserAnimationStyle)
        [ div [ class "form-group" ]
            [ label [ for "name" ] [ text "Name" ]
            , div [ class "input-group" ]
                [ input [ type_ "text", value model.newUserName, onInput UpdateUserName, id "new-user-name-input", class "form-control" ] []
                , div [ class "input-group-append" ]
                    [ button [ onClick SaveUser, class "btn btn-success", type_ "submit" ] [ text "ADD" ] ]
                ]
            ]
        ]


renderKeyedMeetingUser : List User -> User -> ( String, Html Msg )
renderKeyedMeetingUser selectedUsers user =
    let
        activeClass =
            if List.member user selectedUsers then
                " active"

            else
                ""
    in
    ( user.id
    , lazy
        (\u ->
            button [ onClick (ToggleUserMeeting u), class ("list-group-item list-group-item-action" ++ activeClass) ]
                [ text u.name ]
        )
        user
    )


sortedUsers : List User -> List User
sortedUsers participants =
    participants
        |> List.sortWith
            (\a ->
                \b ->
                    compare
                        (String.toLower a.name)
                        (String.toLower b.name)
            )


inputToInt : Int -> String -> Int
inputToInt default value =
    value |> String.toInt |> Maybe.withDefault default


calculateMeetingComplexity : Model -> Int
calculateMeetingComplexity m =
    List.length m.meetingParticipants * m.meetingDuration


renderMeetingParticipant : List User -> String -> Html Msg
renderMeetingParticipant availableUserList id =
    case
        Maybe.map (\user -> user.name) <|
            List.head <|
                List.filter (\user -> user.id == id) availableUserList
    of
        Just name ->
            li [ class "badge badge-secondary mr-1" ] [ text name ]

        Nothing ->
            li [] []


renderKeyedMeetingParticipant : List User -> String -> ( String, Html Msg )
renderKeyedMeetingParticipant participants participant =
    ( participant, lazy (renderMeetingParticipant participants) participant )


renderKeyedMeeting : Model -> Meeting -> ( String, Html Msg )
renderKeyedMeeting model meeting =
    ( meeting.id
    , lazy
        (\m ->
            li [ class "card mb-1" ]
                [ div [ class "card-header" ]
                    [ div [ class "row" ]
                        [ h5 [ class "mr-auto col-auto" ] [ text m.title ]
                        , button [ onClick (DeleteMeeting m), class "col-auto btn btn-sm btn-danger" ]
                            [ Icon.viewIcon Icon.trash ]
                        ]
                    ]
                , div [ class "card-body" ]
                    [ span [ class "card-text text-muted" ]
                        [ text <| String.fromInt m.duration ++ " minutes with "
                        , Html.Keyed.ul
                            [ class "d-inline p-0"
                            ]
                            (List.map (renderKeyedMeetingParticipant model.participants) m.participantIds)
                        ]
                    ]
                , let
                    displayTimes =
                        Dict.get meeting.id model.meetingTimes

                    times =
                        displayTimes
                            |> Maybe.map (\val -> List.sortBy .ord val)
                  in
                  case times of
                    Just meetingTimes ->
                        div [ class "border border-primary card-footer" ]
                            [ div [ class "row align-items-center" ]
                                [ p [ class "col-auto my-0 mr-auto" ]
                                    [ text <|
                                        String.fromInt <|
                                            List.length meetingTimes
                                    , text " Times Available"
                                    ]
                                , button
                                    [ class "col-auto btn btn-sm"
                                    , onClick (ToggleExpandMeetingTime meeting)
                                    ]
                                    [ Icon.viewIcon Icon.chevronDown ]
                                ]
                            , if meeting.expandTimeslots then
                                ul [ class "d-flex flex-column" ]
                                    (List.map
                                        (\time ->
                                            li []
                                                [ text time.time ]
                                        )
                                        meetingTimes
                                    )

                              else
                                div [] []
                            ]

                    Nothing ->
                        div [] []
                ]
        )
        meeting
    )


newMeetingForm : Model -> Html Msg
newMeetingForm model =
    div [ class "col-md-4 col-12" ]
        (if List.length model.meetingParticipants == 0 then
            [ h1 [ class "text-danger" ] [ text "A participant is required to schedule a meeting" ] ]

         else
            [ div [ class "form-group" ]
                [ label [ class "col-form-label col-form-label-lg form-control-label", for "meeting-title" ] [ text "Title*" ]
                , input [ type_ "text", value model.meetingTitle, onInput SetMeetingTitle, Attributes.required True, id "meeting-title", class "form-control form-control-lg" ] []
                ]
            , div [ class "form-group" ]
                [ label [ for "timespan-input" ]
                    [ text <| "Meeting Length: " ++ String.fromInt model.meetingDuration ++ " Minutes" ]
                , input
                    [ onInput (SetMeetingLength << inputToInt 60)
                    , type_ "range"
                    , value <| String.fromInt model.meetingDuration
                    , id "timespan-input"
                    , class "custom-range"
                    , Attributes.min "30"
                    , Attributes.max "120"
                    , step "30"
                    ]
                    []
                ]
            , h6 [] [ text "Preview:" ]
            , if String.isEmpty (String.trim model.meetingTitle) then
                h3 [] [ text "Please name this meeting" ]

              else
                div [ class "card" ]
                    [ h3 [ class "card-header" ] [ text model.meetingTitle ]
                    , div [ class "card-body" ]
                        [ p [ class "card-text" ]
                            [ text <| String.fromInt model.meetingDuration ++ " minute meeting" ]
                        , p [ class "card-text" ]
                            (text "Participants: "
                                :: (model.meetingParticipants
                                        |> List.map (\u -> span [ class "badge badge-secondary mr-1" ] [ text u.name ])
                                   )
                            )
                        ]
                    , div [ class "card-footer" ]
                        [ div [ class "justify-content-end row" ]
                            [ button [ onClick AddMeeting, class "btn btn-success" ]
                                [ span [ class "mr-2" ] [ Icon.viewIcon Icon.save ]
                                , text "Save"
                                ]
                            ]
                        ]
                    ]
            ]
        )


participantView : Model -> List (Html Msg)
participantView model =
    [ div [ class "mt-4 mx-0 border border-secondary row" ]
        [ h1 [ class "display-4 col-auto mr-auto" ]
            [ text "Setup Participants"
            ]
        , button
            [ class "col-auto btn btn-lg"
            , onClick ToggleExpandParticipants
            ]
            [ span [ class "fa-2x" ]
                [ span
                    [ class "badge badge-pill badge-info" ]
                    [ text (String.fromInt <| List.length <| model.participants)
                    , span [ class "ml-2" ] [ Icon.viewIcon Icon.userFriends ]
                    ]
                , let
                    icon =
                        Icon.viewStyled (Animation.render model.participantsChevronAnimationStyle) Icon.chevronDown
                  in
                  span [ class "ml-1" ] [ icon ]
                ]
            ]
        , div
            (Animation.render model.userDropdownStyle
                ++ [ class "container-fluid overflow-auto" ]
            )
            [ div [ class "row" ]
                [ p [ class "col-12 lead" ] [ text "Use this area to add participants that will be involved in meetings. Add new participants and setup their availability by blocking out times on their weekly schedule." ]
                ]
            , div [ class "row" ]
                [ div [ class "col-12" ] [ lazy newUserForm model ] ]
            , div [ class "row p-2" ]
                [ div [ class "col-12 p-0 pr-md-2 mb-2 mb-md-0 col-md-3" ]
                    [ newUserButton model
                    , Html.Keyed.ul
                        [ class "list-group"
                        , style "max-height" "50vh"
                        , style "overflow-y" "auto"
                        ]
                        (List.map
                            (renderKeyedUser
                                model.selectedUser
                            )
                            (sortedUsers model.participants)
                        )
                    ]
                , div [ class "col-sm-12 col-md-9" ]
                    [ div [ class "row mb-2" ]
                        (case model.selectedUser of
                            Just user ->
                                [ h3 [ class "col-auto mr-auto" ] [ text (user.name ++ "'s Schedule:") ]
                                , button [ class "col-auto btn btn-danger", onClick (DeleteUser user) ]
                                    [ span [ class "mr-1" ] [ Icon.viewIcon Icon.trash ]
                                    , text user.name
                                    ]
                                ]

                            Nothing ->
                                []
                        )
                    , div [ class "row calendar-container" ]
                        [ div [ class "col-12 p-0", id "participant-calendar" ] []
                        ]
                    ]
                ]
            ]
        ]
    ]


meetingView : Model -> List (Html Msg)
meetingView model =
    [ div [ class "mt-4 mx-0 border border-secondary row" ]
        [ h1 [ class "display-4 col-auto mr-auto" ]
            [ text "Configure Meetings"
            ]
        , button
            [ class "col-auto btn btn-lg"
            , onClick ToggleExpandMeetings
            ]
            [ span
                [ class "fa-2x" ]
                [ span [ class "badge badge-pill badge-info" ]
                    [ text
                        (String.fromInt <| List.length <| model.meetings)
                    , span [ class "ml-2" ] [ Icon.viewIcon Icon.calendarAlt ]
                    ]
                , let
                    icon =
                        Icon.viewStyled (Animation.render model.meetingChevronAnimationStyle) Icon.chevronDown
                  in
                  span [ class "ml-1" ] [ icon ]
                ]
            ]
        , div
            (Animation.render model.meetingDropdownStyle
                ++ [ class "container-fluid overflow-auto" ]
            )
            [ div [ class "row" ]
                [ p [ class "col-12 lead" ]
                    [ text "Use this area to setup the types of meetings you will need in the final step. These will be batched all at once when computing the final results, so they need to all be setup now. "
                    , mark [] [ strong [] [ text "It is expected that YOU are a participant in each of the meetings. You do not need to setup your own schedule yet. That will happen in the final step." ] ]
                    ]
                ]
            , div [ class "row p-2" ]
                [ div [ class "col-12 p-0 pr-md-2 mb-2 mb-md-0 col-md-3" ]
                    [ h3 [ class "text-truncate" ] [ text "Participants*" ]
                    , Html.Keyed.ul
                        [ class "list-group"
                        , style "max-height" "50vh"
                        , style "overflow-y" "auto"
                        ]
                        (List.map
                            (renderKeyedMeetingUser model.meetingParticipants)
                            (sortedUsers model.participants)
                        )
                    ]
                , newMeetingForm model
                , div
                    [ class "col-md-5 p-0 col-12"
                    ]
                    [ h3 [] [ text "Meetings:" ]
                    , Html.Keyed.ul
                        [ style "max-height" "50vh"
                        , style "overflow-y" "auto"
                        , class "p-0"
                        ]
                        (List.map
                            (renderKeyedMeeting model)
                            model.meetings
                        )
                    ]
                ]
            ]
        ]
    ]


finalStep : Model -> List (Html Msg)
finalStep model =
    [ div [ class "mt-4 mx-0 border border-secondary row" ]
        [ h1 [ class "display-4 col-auto mr-auto" ]
            [ text "Select Available Times" ]
        , div [ class "container-fluid overflow-auto" ]
            [ div [ class "row" ]
                [ p [ class "col-12 lead" ]
                    [ text "This is the last step. Here you will define your availability in the calendar below. Zeitplan will use these times (and only these times) to attempt to schedule each of the meetings defined above. This could take a long time to run! Please be patient, and try not to get frustrated." ]
                ]
            , div [ class "row" ]
                [ div [ class "col-12 calendar-container" ]
                    [ div [ id "final-calendar" ] []
                    ]
                , button [ class "btn btn-lg btn-block m-1 btn-secondary", onClick RunScheduler ] [ text "Recompute Schedule" ]
                ]
            ]
        ]
    ]


renderFooter : Model -> Html Msg
renderFooter model =
    footer [ id "footer", class "bg-dark mt-4 position-sticky" ]
        [ div [ class "container-fluid text-center" ]
            [ blockquote [ class "blockquote mb-0" ]
                [ p [] [ text "This project was made with love for Professor Victor Drescher at Southeastern Louisiana University. He believed in this project even before I was capable of finishing." ]
                , footer [ class "blockquote-footer" ] [ text "Made possible in Elm, with major help from the Fullcalendar library. The desktop application is running on Tauri, and the primary computations are written in Rust" ]
                ]
            ]
        ]


renderResults : Model -> List (Html Msg)
renderResults model =
    [ div [ class "mt-4 mx-0 border border-secondary row" ]
        [ h1 [ class "display-4 col-12" ]
            [ text "Computed Schedule"
            ]
        , div [ class "container-fluid mx-1" ]
            [ Html.Keyed.ul
                [ style "max-height" "50vh"
                , style "overflow-y" "auto"
                , class "p-0 result-container"
                ]
                (model.meetings
                    |> List.filter (\m -> Dict.member m.id model.results)
                    |> List.map
                        (renderKeyedResultMeeting model)
                )
            ]
        ]
    ]


renderKeyedResultMeeting : Model -> Meeting -> ( String, Html Msg )
renderKeyedResultMeeting model meeting =
    ( meeting.id
    , lazy
        (\m ->
            let
                meetingResult =
                    Dict.get meeting.id model.results

                ( cardStyle, textStyle, timeText ) =
                    case meetingResult of
                        Just result ->
                            if result.status == "Scheduled" then
                                ( " border-success"
                                , " text-success"
                                , Nothing
                                )

                            else
                                ( " border-danger"
                                , " text-danger"
                                , Just "Sorry, unable to schedule this meeting"
                                )

                        Nothing ->
                            ( " d-none", " d-none", Nothing )
            in
            case meetingResult of
                Just result ->
                    li
                        [ class <| "p-0 mb-1 card" ++ cardStyle
                        ]
                        [ div [ class "card-header" ]
                            [ div [ class "row" ]
                                [ h3 [ class <| "col-auto" ++ textStyle ] [ text m.title ]
                                ]
                            ]
                        , div [ class "card-body" ]
                            [ span [ class <| "card-text" ++ textStyle ]
                                [ text <| String.fromInt m.duration ++ " minutes with "
                                , Html.Keyed.ul
                                    [ class "d-inline p-0"
                                    ]
                                    (List.map (renderKeyedMeetingParticipant model.participants) m.participantIds)
                                ]
                            ]
                        , div [ class "card-footer" ]
                            [ h6 [ class textStyle ]
                                (case timeText of
                                    Nothing ->
                                        [ text result.time ]

                                    Just t ->
                                        [ text t ]
                                )
                            ]
                        ]

                Nothing ->
                    div [] []
        )
        meeting
    )


view : Model -> Document Msg
view model =
    { title = "Zeitplan"
    , body =
        [ Icon.css
        , nav [ class "sticky-top navbar navbar-expand-lg navbar-dark bg-primary" ]
            [ h3 [ class "navbar-brand" ]
                [ text "Zeitplan" ]
            ]
        , div [ class "container" ]
            (participantView model
                ++ meetingView model
                ++ finalStep model
                ++ renderResults model
            )
        , renderFooter model
        ]
    }



-- PORTS


decodeUsers : Decoder (List User)
decodeUsers =
    Decode.list userDecoder


userDecoder : Decoder User
userDecoder =
    Decode.succeed User
        |> Pipeline.required "id" string
        |> Pipeline.required "name" string


decodeMeetings : Decoder (List Meeting)
decodeMeetings =
    Decode.list meetingDecoder


meetingDecoder : Decoder Meeting
meetingDecoder =
    Decode.succeed Meeting
        |> Pipeline.required "id" string
        |> Pipeline.required "title" string
        |> Pipeline.required "participantIds" (list string)
        |> Pipeline.required "duration" int
        |> Pipeline.hardcoded False


decodeMeetingTimeslot : Decoder MeetingTimeslot
decodeMeetingTimeslot =
    Decode.succeed MeetingTimeslot
        |> Pipeline.required "ord" int
        |> Pipeline.required "time" string


decodeTimeslots : Decoder (Dict.Dict String (List MeetingTimeslot))
decodeTimeslots =
    Decode.dict (list decodeMeetingTimeslot)


decodeResults : Decoder (Dict.Dict String ResultStatus)
decodeResults =
    Decode.dict
        (Decode.succeed ResultStatus
            |> Pipeline.required "status" string
            |> Pipeline.required "time" string
            |> Pipeline.optional "ord" int -1
        )


port loadUsers : (Decode.Value -> msg) -> Sub msg


port loadMeetings : (Decode.Value -> msg) -> Sub msg


port saveMeetingTimeslots : (Decode.Value -> msg) -> Sub msg


port renderComputedSchedule : (Decode.Value -> msg) -> Sub msg


port saveUsers : List User -> Cmd msg


port processWithTauri : List Meeting -> Cmd msg


port saveMeetings : List Meeting -> Cmd msg


port getMeetingTimes : List Meeting -> Cmd msg


port destroyCalendar : () -> Cmd msg


port deleteUser : User -> Cmd msg


port loadUserWithEvents : User -> Cmd msg


port updateUser : (Decode.Value -> msg) -> Sub msg


port updateMainCalendar : (() -> msg) -> Sub msg



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ loadUsers LoadUsers
        , loadMeetings LoadMeetings
        , saveMeetingTimeslots SaveMeetingAvailableTimeslots
        , renderComputedSchedule DisplayComputedSchedule
        , updateUser RefreshMeetingsWithUserId
        , updateMainCalendar RefreshAllMeetings
        , Animation.subscription Animate [ model.userDropdownStyle ]
        , Animation.subscription Animate [ model.meetingDropdownStyle ]
        , Animation.subscription Animate [ model.participantsChevronAnimationStyle ]
        , Animation.subscription Animate [ model.meetingChevronAnimationStyle ]
        , Animation.subscription Animate [ model.newUserAnimationStyle ]
        ]


type alias Flags =
    ()


main : Program Flags Model Msg
main =
    Browser.document
        { init = \_ -> init
        , subscriptions = subscriptions
        , update = update
        , view = view
        }
