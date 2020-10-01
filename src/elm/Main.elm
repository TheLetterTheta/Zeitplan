port module Main exposing (Meeting, MeetingTimeslot, ResultStatus, User, decodeMeetings, decodeResults, decodeTimeslots, decodeUsers, main)

import Animation exposing (rad)
import Animation.Spring.Presets exposing (stiff)
import Bootstrap.Badge as Badge
import Bootstrap.Button as Button
import Bootstrap.Form as Form
import Bootstrap.Form.Checkbox as Checkbox
import Bootstrap.Form.Input as Input
import Bootstrap.Form.InputGroup as InputGroup
import Bootstrap.Grid as Grid
import Bootstrap.Grid.Col as Col
import Bootstrap.Grid.Row as Row
import Bootstrap.Navbar as Navbar
import Bootstrap.Utilities.Border as Border
import Bootstrap.Utilities.Display as Display
import Bootstrap.Utilities.Flex as Flex
import Bootstrap.Utilities.Spacing as Spacing
import Browser exposing (Document)
import Browser.Dom as Dom
import Debug
import Dict
import FontAwesome.Icon as Icon exposing (Icon)
import FontAwesome.Solid as Icon
import FontAwesome.Styles as Icon
import Html exposing (Html, blockquote, button, div, footer, h1, h3, h5, h6, img, input, li, mark, p, span, strong, text, ul)
import Html.Attributes as Attributes exposing (attribute, class, for, id, max, min, name, required, src, step, style, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
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
    , isExpandMeetings : Bool
    , isExpandParticipants : Bool
    , isExpandToggleNewUserForm : Bool
    , meetingChevronAnimationStyle : Animation.State
    , meetingDropdownStyle : Animation.State
    , meetingDuration : Int
    , meetingParticipants : List User
    , meetingTimes : Dict.Dict String (List MeetingTimeslot)
    , meetingTitle : String
    , meetings : List Meeting
    , navbarState : Navbar.State
    , newUserAnimationStyle : Animation.State
    , newUserName : String
    , participantsChevronAnimationStyle : Animation.State
    , results : Dict.Dict String ResultStatus
    , selectedUser : Maybe User
    , useComplexComputation : Bool
    , userDropdownStyle : Animation.State
    }


init : ( Model, Cmd Msg )
init =
    let
        ( navbarState, navbarCmd ) =
            Navbar.initialState NavbarMsg
    in
    ( { isExpandToggleNewUserForm = False
      , isExpandMeetings = False
      , isExpandParticipants = False
      , meetingChevronAnimationStyle = initialChevronStyle
      , meetingDropdownStyle = initialDropdownStyle
      , meetingDuration = 60
      , meetingParticipants = []
      , meetingTimes = Dict.empty
      , meetingTitle = ""
      , meetings = []
      , navbarState = navbarState
      , newUserAnimationStyle = initialDropdownStyle
      , newUserName = ""
      , participants = []
      , participantsChevronAnimationStyle = initialChevronStyle
      , results = Dict.empty
      , selectedUser = Nothing
      , useComplexComputation = False
      , userDropdownStyle = initialDropdownStyle
      }
    , navbarCmd
    )



-- UPDATE


type Msg
    = SelectUser User
    | AddMeeting
    | Animate Animation.Msg
    | DeleteMeeting Meeting
    | DeleteUser User
    | DisplayComputedSchedule Decode.Value
    | LoadMeetings Decode.Value
    | LoadUsers Decode.Value
    | NavbarMsg Navbar.State
    | RefreshAllMeetings ()
    | RefreshMeetingsWithUserId Decode.Value
    | RunScheduler
    | SaveMeetingAvailableTimeslots Decode.Value
    | SaveMeetingWithId Time.Posix
    | SaveUser
    | SaveUserWithId Time.Posix
    | SetMeetingLength Int
    | SetMeetingTitle String
    | ToggleExpandMeetingTime Meeting
    | ToggleExpandMeetings
    | ToggleExpandParticipants
    | ToggleNewUserForm
    | ToggleUseComplexComputation Bool
    | ToggleUserMeeting User
    | UpdateUserName String
    | NoOp


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        NavbarMsg navbarState ->
            ( { model | navbarState = navbarState }, Cmd.none )

        ToggleUseComplexComputation checkVal ->
            ( { model | useComplexComputation = checkVal }, Cmd.none )

        RunScheduler ->
            if model.useComplexComputation then
                ( model, processAllWithTauri model.meetings )

            else
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
        ( buttonType, icon, buttonText ) =
            if not model.isExpandToggleNewUserForm then
                ( Button.success, Icon.userPlus, "Show" )

            else
                ( Button.danger, Icon.userTimes, "Hide" )

        classList =
            "text-center"
    in
    Button.button
        [ buttonType
        , Button.block
        , Button.attrs
            [ class classList
            , onClick ToggleNewUserForm
            ]
        ]
        [ Icon.viewIcon icon, p [ Spacing.m0 ] [ text buttonText ] ]


newUserForm : Model -> Html Msg
newUserForm model =
    div (Animation.render model.newUserAnimationStyle)
        [ Form.form [ onSubmit SaveUser ]
            [ Form.group []
                [ Form.label [ for "name" ] [ text "Name" ]
                , InputGroup.config
                    (InputGroup.text
                        [ Input.placeholder "User name"
                        , Input.attrs [ value model.newUserName, onInput UpdateUserName, id "new-user-name-input" ]
                        ]
                    )
                    |> InputGroup.successors
                        [ InputGroup.button [ Button.success, Button.attrs [ onClick SaveUser ] ] [ text "ADD" ] ]
                    |> InputGroup.view
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
            Badge.pillSecondary [ Spacing.mr1 ] [ text name ]

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
            li [ Spacing.mb1, class "card" ]
                [ div [ class "card-header" ]
                    [ Grid.row []
                        [ Grid.col []
                            [ h5 [ Spacing.mrAuto ] [ text m.title ]
                            ]
                        , Grid.col [ Col.xsAuto ]
                            [ Button.button [ Button.attrs [ onClick (DeleteMeeting m) ], Button.danger ]
                                [ Icon.viewIcon Icon.trash ]
                            ]
                        ]
                    ]
                , div [ class "card-body" ]
                    [ span [ class "card-text" ]
                        [ text <| String.fromInt m.duration ++ " minutes with "
                        , Html.Keyed.ul
                            [ Spacing.p0
                            , Display.inline
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
                        div [ Border.top, Border.primary, class "card-footer" ]
                            [ Grid.row [ Row.middleXs ]
                                [ Grid.col []
                                    [ p [ Spacing.mrAuto, Spacing.my0 ]
                                        [ text <|
                                            String.fromInt <|
                                                List.length meetingTimes
                                        , text " Times Available"
                                        ]
                                    ]
                                , Grid.col [ Col.xsAuto ]
                                    [ Button.button
                                        [ Button.small
                                        , Button.attrs [ class "text-muted", onClick (ToggleExpandMeetingTime meeting) ]
                                        ]
                                        [ Icon.viewIcon Icon.chevronDown ]
                                    ]
                                ]
                            , if meeting.expandTimeslots then
                                ul []
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


newMeetingForm : Model -> Grid.Column Msg
newMeetingForm model =
    Grid.col [ Col.md4 ]
        (if List.length model.meetingParticipants == 0 then
            [ h1 [ class "text-danger" ] [ text "A participant is required to schedule a meeting" ] ]

         else
            [ Form.group []
                [ Form.label [ class "col-form-label-lg", for "meeting-title" ] [ text "Title*" ]
                , Input.text
                    [ Input.value model.meetingTitle
                    , Input.onInput SetMeetingTitle
                    , Input.placeholder "Meeting title"
                    , Input.large
                    , Input.id "meeting-title"
                    , Input.attrs [ Attributes.required True ]
                    ]
                ]
            , Form.group []
                [ Form.label [ for "timespan-input" ]
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
                                        |> List.map (\u -> Badge.badgeSecondary [ Spacing.mr1 ] [ text u.name ])
                                   )
                            )
                        ]
                    , div [ class "card-footer" ]
                        [ Grid.row [ Row.attrs [ Flex.justifyEnd ] ]
                            [ Grid.col [ Col.xsAuto ]
                                [ Button.button [ Button.success, Button.attrs [ onClick AddMeeting ] ]
                                    [ span [ Spacing.mr2 ] [ Icon.viewIcon Icon.save ]
                                    , text "Save"
                                    ]
                                ]
                            ]
                        ]
                    ]
            ]
        )


participantView : Model -> Html Msg
participantView model =
    Grid.row [ Row.attrs [ Spacing.mx0, Spacing.mt4, Border.all, Border.secondary ] ]
        [ Grid.col [ Col.xs ]
            [ h1 [ class "display-4" ]
                [ text "Setup Participants"
                ]
            ]
        , Grid.col [ Col.xsAuto, Col.attrs [ Spacing.pr0 ] ]
            [ Button.button
                [ Button.large
                , Button.attrs [ onClick ToggleExpandParticipants ]
                ]
                [ span [ class "fa-2x" ]
                    [ Badge.pillInfo
                        []
                        [ text (String.fromInt <| List.length <| model.participants)
                        , span [ Spacing.ml2 ] [ Icon.viewIcon Icon.userFriends ]
                        ]
                    , let
                        icon =
                            Icon.viewStyled (Animation.render model.participantsChevronAnimationStyle) Icon.chevronDown
                      in
                      span [ Spacing.ml1, class "text-muted" ] [ icon ]
                    ]
                ]
            ]
        , Grid.col [ Col.xs12 ]
            [ Grid.containerFluid
                (class "overflow-auto"
                    :: Animation.render model.userDropdownStyle
                )
                [ Grid.row []
                    [ Grid.col []
                        [ p [ class "lead" ] [ text "Use this area to add participants that will be involved in meetings. Add new participants and setup their availability by blocking out times on their weekly schedule." ]
                        ]
                    ]
                , Grid.row []
                    [ Grid.col [] [ lazy newUserForm model ] ]
                , Grid.row [ Row.attrs [ Spacing.p2 ] ]
                    [ Grid.col [ Col.md3, Col.attrs [ Spacing.mb2, Spacing.mb0Md, Spacing.p0, Spacing.pr2Md ] ]
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
                    , Grid.col [ Col.sm12, Col.md9 ]
                        [ Grid.row [ Row.attrs [ Spacing.mb2 ] ]
                            (case model.selectedUser of
                                Just user ->
                                    [ Grid.col [ Col.attrs [ Spacing.p0 ] ] [ h3 [ Spacing.mrAuto ] [ text (user.name ++ "'s Schedule:") ] ]
                                    , Grid.col [ Col.xsAuto, Col.attrs [ Spacing.p0 ] ]
                                        [ Button.button [ Button.danger, Button.attrs [ onClick (DeleteUser user) ] ]
                                            [ span [ Spacing.mr1 ] [ Icon.viewIcon Icon.trash ]
                                            , text user.name
                                            ]
                                        ]
                                    ]

                                Nothing ->
                                    []
                            )
                        , Grid.row [ Row.attrs [ class "calendar-container" ] ]
                            [ Grid.col [ Col.attrs [ Spacing.p0, id "participant-calendar" ] ] []
                            ]
                        ]
                    ]
                ]
            ]
        ]


meetingView : Model -> Html Msg
meetingView model =
    Grid.row [ Row.attrs [ Spacing.mt4, Spacing.mx0, Border.all, Border.secondary ] ]
        [ Grid.col [ Col.attrs [ Spacing.mrAuto ] ]
            [ h1 [ class "display-4" ]
                [ text "Configure Meetings"
                ]
            ]
        , Grid.col [ Col.xsAuto, Col.attrs [ Spacing.pr0 ] ]
            [ Button.button
                [ Button.large
                , Button.attrs [ onClick ToggleExpandMeetings ]
                ]
                [ span
                    [ class "fa-2x" ]
                    [ Badge.pillInfo []
                        [ text
                            (String.fromInt <| List.length <| model.meetings)
                        , span [ Spacing.ml2 ] [ Icon.viewIcon Icon.calendarAlt ]
                        ]
                    , let
                        icon =
                            Icon.viewStyled (Animation.render model.meetingChevronAnimationStyle) Icon.chevronDown
                      in
                      span [ Spacing.ml1, class "text-muted" ] [ icon ]
                    ]
                ]
            ]
        , Grid.col [ Col.xs12 ]
            [ Grid.containerFluid
                (Animation.render model.meetingDropdownStyle
                    ++ [ class "overflow-auto" ]
                )
                [ Grid.row []
                    [ Grid.col [ Col.xs12 ]
                        [ p [ class "lead" ]
                            [ text "Use this area to setup the types of meetings you will need in the final step. These will be batched all at once when computing the final results, so they need to all be setup now. "
                            , mark [] [ strong [] [ text "It is expected that YOU are a participant in each of the meetings. You do not need to setup your own schedule yet. That will happen in the final step." ] ]
                            ]
                        ]
                    ]
                , Grid.row [ Row.attrs [ Spacing.p2 ] ]
                    [ Grid.col [ Col.md3, Col.attrs [ Spacing.mb2, Spacing.mb0Md, Spacing.p0, Spacing.pr2Md ] ]
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
                    , Grid.col [ Col.md5, Col.attrs [ Spacing.p0 ] ]
                        [ h3 [] [ text "Meetings:" ]
                        , Html.Keyed.ul
                            [ style "max-height" "50vh"
                            , style "overflow-y" "auto"
                            , Spacing.p0
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


finalStep : Model -> Html Msg
finalStep model =
    Grid.row [ Row.attrs [ Spacing.mt4, Spacing.mx0, Border.all, Border.secondary ] ]
        [ Grid.col [ Col.xsAuto, Col.attrs [ Spacing.mrAuto ] ]
            [ h1 [ class "display-4" ]
                [ text "Select Available Times" ]
            ]
        , Grid.col [ Col.xs12 ]
            [ Grid.containerFluid [ class "overflow-auto" ]
                [ Grid.row []
                    [ Grid.col []
                        [ p [ class "lead" ]
                            [ text "This is the last step. Here you will define your availability in the calendar below. Zeitplan will use these times (and only these times) to attempt to schedule each of the meetings defined above. This could take a long time to run! Please be patient, and try not to get frustrated." ]
                        ]
                    ]
                , Grid.row []
                    [ Grid.col [ Col.attrs [ class "calendar-container" ] ]
                        [ div [ id "final-calendar" ] []
                        ]
                    ]
                , Grid.row []
                    [ Grid.col []
                        [ Button.button [ Button.block, Button.large, Button.secondary, Button.attrs [ onClick RunScheduler, Spacing.m1 ] ] [ text "Recompute Schedule" ]
                        , div [ Spacing.m1 ]
                            [ Checkbox.checkbox
                                [ Checkbox.attrs [ Spacing.ml1 ]
                                , Checkbox.danger
                                , Checkbox.onCheck ToggleUseComplexComputation
                                , Checkbox.inline
                                , Checkbox.checked model.useComplexComputation
                                ]
                                "Try all combinations. DANGER: This has the potential to run for a VERY long time"
                            ]
                        ]
                    ]
                ]
            ]
        ]


renderFooter : Model -> Html Msg
renderFooter model =
    footer [ id "footer", Spacing.mt4, class "bg-dark-less-opaque position-sticky" ]
        [ Grid.containerFluid [ class "text-center text-white" ]
            [ blockquote [ Spacing.mb0, class "blockquote" ]
                [ p [] [ text "This project was made possible thanks to Professor Victor Drescher at Southeastern Louisiana University." ]
                , footer [ class "text-white text-muted blockquote-footer" ] [ text "UI thanks to Elm + Bootstrap + Bootswatch + Fullcalendar. Any complicated logic is handled in Rust thanks to the wonderful work being done on the Tauri Project." ]
                ]
            ]
        ]


renderResults : Model -> Html Msg
renderResults model =
    Grid.row [ Row.attrs [ Spacing.mx0, Spacing.mt4, Border.all, Border.secondary ] ]
        [ Grid.col [ Col.xs12 ]
            [ h1 [ class "display-4" ]
                [ text "Computed Schedule"
                ]
            ]
        , Grid.col [ Col.xs12 ]
            [ Grid.containerFluid [ Spacing.mx1 ]
                [ Html.Keyed.ul
                    [ style "max-height" "50vh"
                    , style "overflow-y" "auto"
                    , class "result-container"
                    , Spacing.p0
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
                                ( Border.success
                                , " text-success"
                                , Nothing
                                )

                            else
                                ( Border.danger
                                , " text-danger"
                                , Just "Sorry, unable to schedule this meeting"
                                )

                        Nothing ->
                            ( Display.none, " d-none", Nothing )
            in
            case meetingResult of
                Just result ->
                    li
                        [ class "card"
                        , Border.all
                        , cardStyle
                        , Spacing.mb1
                        , Spacing.p0
                        ]
                        [ div [ class "card-header" ]
                            [ Grid.row []
                                [ Grid.col [] [ h3 [ class textStyle ] [ text m.title ] ]
                                ]
                            ]
                        , div [ class "card-body" ]
                            [ span [ class <| "card-text" ++ textStyle ]
                                [ text <| String.fromInt m.duration ++ " minutes with "
                                , Html.Keyed.ul
                                    [ Display.inline
                                    , Spacing.p0
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
        , Navbar.config NavbarMsg
            |> Navbar.attrs [ class "sticky-top" ]
            |> Navbar.withAnimation
            |> Navbar.primary
            |> Navbar.brand []
                [ img
                    [ src "Zeitplan.svg"
                    , style "width" "30px"
                    ]
                    []
                , h1
                    [ Spacing.ml2, class "navbar-brand" ]
                    [ text "Zeitplan" ]
                ]
            |> Navbar.view model.navbarState
        , Grid.container []
            [ participantView model
            , meetingView model
            , finalStep model
            , renderResults model
            ]
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


port processAllWithTauri : List Meeting -> Cmd msg



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
        , Navbar.subscriptions model.navbarState NavbarMsg
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
