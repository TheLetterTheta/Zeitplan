port module Main exposing (main)

import Browser exposing (Document)
import Browser.Dom as Dom
import FontAwesome.Icon as Icon exposing (Icon)
import FontAwesome.Solid as Icon
import FontAwesome.Styles as Icon
import Html exposing (Html, br, button, div, form, h1, h3, h5, h6, i, input, label, li, mark, nav, p, span, strong, text, ul)
import Html.Attributes as Attributes exposing (attribute, class, for, id, max, min, name, required, step, style, type_, value)
import Html.Events exposing (onClick, onInput)
import Html.Keyed
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
    }


type alias Model =
    { users : List User
    , selectedUser : Maybe User
    , newUserName : String
    , currentlyAddingUser : Bool
    , expandParticipants : Bool
    , expandMeetings : Bool
    , meetingUsers : List User
    , meetingLength : Int
    , meetingTitle : String
    , meetings : List Meeting
    }


init : ( Model, Cmd Msg )
init =
    ( { currentlyAddingUser = False
      , users = []
      , selectedUser = Nothing
      , meetings = []
      , newUserName = ""
      , expandParticipants = False
      , expandMeetings = False
      , meetingUsers = []
      , meetingLength = 60
      , meetingTitle = ""
      }
    , Cmd.none
    )



-- VIEW


renderKeyedUser : Maybe User -> User -> ( String, Html Msg )
renderKeyedUser selectedUser user =
    let
        classes =
            "list-group-item list-group-item-action"
                ++ (if Just user == selectedUser then
                        " active"

                    else
                        ""
                   )
    in
    ( user.id
    , button [ onClick (SelectUser user), class classes ]
        [ text user.name ]
    )


newUserButton : Model -> Html Msg
newUserButton model =
    let
        ( buttonClass, icon, buttonText ) =
            if not model.currentlyAddingUser then
                ( "btn-success", Icon.userPlus, "Show" )

            else
                ( "btn-danger", Icon.userTimes, "Hide" )

        classList =
            buttonClass ++ " list-group-item list-group-item-action text-center"
    in
    button
        [ class classList
        , onClick NewUser
        ]
        [ Icon.viewIcon icon, p [ class "m-0" ] [ text buttonText ] ]


newUserForm : Model -> Html Msg
newUserForm model =
    div
        [ class <|
            "collapse"
                ++ (if model.currentlyAddingUser then
                        " show"

                    else
                        ""
                   )
        , id "new-user-form"
        ]
        [ div [ class "form-group" ]
            [ label [ for "name" ] [ text "Name" ]
            , div [ class "input-group" ]
                [ input [ type_ "text", value model.newUserName, onInput UpdateUserName, id "new-user-name-input", class "form-control" ] []
                , div [ class "input-group-append" ]
                    [ button [ onClick SaveUser, class "btn btn-success", type_ "submit" ] [ text "ADD" ] ]
                ]
            ]
        ]


participantView : Model -> List (Html Msg)
participantView model =
    [ div [ class "mt-4 mx-0 border border-primary row" ]
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
                    [ text (String.fromInt <| List.length <| model.users)
                    , span [ class "ml-2" ] [ Icon.viewIcon Icon.userFriends ]
                    ]
                , let
                    icon =
                        Icon.viewIcon <|
                            if model.expandParticipants then
                                Icon.chevronUp

                            else
                                Icon.chevronDown
                  in
                  span [ class "ml-1" ] [ icon ]
                ]
            ]
        , div
            [ id "participant-content"
            , class <|
                "collapse container-fluid"
                    ++ (if model.expandParticipants then
                            " show"

                        else
                            ""
                       )
            ]
            [ div [ class "row" ]
                [ p [ class "col-12 lead" ] [ text "Use this area to add participants that will be involved in meetings. Add new participants and setup their availability by blocking out times on their weekly schedule." ]
                ]
            , div [ class "row" ]
                [ div [ class "col-12" ] [ newUserForm model ] ]
            , div [ class "row p-2" ]
                [ div [ class "col-12 p-0 pr-md-2 mb-2 mb-md-0 col-md-3" ]
                    [ newUserButton model
                    , Html.Keyed.ul
                        [ class "list-group"
                        , style "max-height" "80vh"
                        , style "overflow-y" "auto"
                        ]
                        (List.map
                            (renderKeyedUser
                                model.selectedUser
                            )
                            (sortedUsers model.users)
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
                    , div [ class "row" ]
                        [ div [ class "col-12 p-0", id "calendar" ] []
                        ]
                    ]
                ]
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
    , button [ onClick (ToggleUserMeeting user), class ("list-group-item list-group-item-action" ++ activeClass) ]
        [ text user.name ]
    )


sortedUsers : List User -> List User
sortedUsers users =
    users
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
    List.length m.meetingUsers * m.meetingLength


renderMeetingParticipant : List User -> String -> Html Msg
renderMeetingParticipant users id =
    case
        Maybe.map (\user -> user.name) <|
            List.head <|
                List.filter (\user -> user.id == id) users
    of
        Just name ->
            span [ class "badge badge-primary mr-1" ] [ text name ]

        Nothing ->
            span [] []


renderMeeting : Model -> Meeting -> Html Msg
renderMeeting model meeting =
    div [ class "card" ]
        [ div [ class "card-header" ]
            [ div [ class "row" ]
                [ h5 [ class "mr-auto col-auto" ] [ text meeting.title ]
                , button [ onClick (DeleteMeeting meeting), class "col-auto btn btn-sm btn-danger" ]
                    [ Icon.viewIcon Icon.trash ]
                ]
            ]
        , div [ class "card-body" ]
            [ p [ class "card-text text-muted" ]
                [ text <| String.fromInt meeting.duration ++ " minutes with "
                , span [ class "card-text text-muted" ]
                    (List.map (renderMeetingParticipant model.users) meeting.participantIds)
                ]
            ]
        ]


meetingView : Model -> List (Html Msg)
meetingView model =
    [ div [ class "mt-4 mx-0 border border-primary row" ]
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
                        Icon.viewIcon <|
                            if model.expandMeetings then
                                Icon.chevronUp

                            else
                                Icon.chevronDown
                  in
                  span [ class "ml-1" ] [ icon ]
                ]
            ]
        , div
            [ id "meeting-content"
            , class <|
                "collapse container-fluid"
                    ++ (if model.expandMeetings then
                            " show"

                        else
                            ""
                       )
            ]
            [ div [ class "row" ]
                [ p [ class "col-12 lead" ]
                    [ text "Use this area to setup the types of meetings you will need in the final step. These will be batched all at once when computing the final results, so they need to all be setup now. "
                    , mark [] [ strong [] [ text "It is expected that YOU are a participant in each of the meetings. You do not need to setup your own schedule yet. That will happen in the final step." ] ]
                    ]
                ]
            , div [ class "row p-2" ]
                [ div [ class "col-md-3 col-12" ]
                    [ h3 [ class "text-truncate" ] [ text "Participants*" ]
                    , Html.Keyed.ul
                        [ class "list-group"
                        , style "max-height" "80vh"
                        , style "overflow-y" "auto"
                        ]
                        (List.map
                            (renderKeyedMeetingUser model.meetingUsers)
                            (sortedUsers model.users)
                        )
                    ]
                , div [ class "col-md-5 col-12" ]
                    (if List.length model.meetingUsers == 0 then
                        [ h1 [ class "text-warning" ] [ text "A participant is required to schedule a meeting" ] ]

                     else
                        [ div [ class "form-group" ]
                            [ label [ class "col-form-label col-form-label-lg form-control-label", for "meeting-title" ] [ text "Title*" ]
                            , input [ type_ "text", value model.meetingTitle, onInput SetMeetingTitle, Attributes.required True, id "meeting-title", class "form-control form-control-lg" ] []
                            ]
                        , div [ class "form-group" ]
                            [ label [ for "timespan-input" ]
                                [ text <| "Meeting Length: " ++ String.fromInt model.meetingLength ++ " Minutes" ]
                            , input
                                [ onInput (SetMeetingLength << inputToInt 60)
                                , type_ "range"
                                , value <| String.fromInt model.meetingLength
                                , id "timespan-input"
                                , class "custom-range"
                                , Attributes.min "15"
                                , Attributes.max "120"
                                , step "15"
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
                                        [ text <| String.fromInt model.meetingLength ++ " minute meeting" ]
                                    , p [ class "card-text" ]
                                        (text "Participants: "
                                            :: (model.meetingUsers
                                                    |> List.map (\u -> span [ class "badge badge-primary mr-1" ] [ text u.name ])
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
                , div
                    [ class "col-md-4 col-12"
                    , style "max-height" "80vh"
                    , style "overflow-y" "auto"
                    ]
                    (List.map
                        (renderMeeting model)
                        model.meetings
                    )
                ]
            ]
        ]
    ]


view : Model -> Document Msg
view model =
    { title = "Zeitplan"
    , body =
        [ Icon.css
        , nav [ class "sticky-top navbar navbar-expand-lg navbar-dark bg-primary" ]
            [ h3 [ class "navbar-brand" ] [ text "Zeitplan" ]
            ]
        , div [ class "container" ]
            (participantView model
                ++ meetingView model
            )
        ]
    }



-- UPDATE


type Msg
    = SelectUser User
    | NewUser
    | UpdateUserName String
    | DeleteMeeting Meeting
    | SaveUser
    | SaveUserWithId Time.Posix
    | ToggleExpandParticipants
    | ToggleExpandMeetings
    | ToggleUserMeeting User
    | LoadUsers Decode.Value
    | LoadMeetings Decode.Value
    | DeleteUser User
    | AddMeeting
    | SetMeetingLength Int
    | SetMeetingTitle String
    | SaveMeetingWithId Time.Posix
    | NoOp


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Cmd.none )

        AddMeeting ->
            ( model, Task.perform SaveMeetingWithId Time.now )

        DeleteMeeting meeting ->
            let
                newMeetings =
                    List.filter (\m -> m /= meeting) model.meetings
            in
            ( { model | meetings = newMeetings }
            , saveMeetings newMeetings
            )

        SaveMeetingWithId currentTimestamp ->
            let
                newMeeting : Meeting
                newMeeting =
                    { id =
                        String.fromInt <|
                            Time.posixToMillis currentTimestamp
                    , title = model.meetingTitle
                    , participantIds = List.map (\u -> u.id) model.meetingUsers
                    , duration = model.meetingLength
                    }

                newMeetings =
                    newMeeting :: model.meetings
            in
            ( { model
                | meetingUsers = []
                , meetings = newMeetings
              }
            , saveMeetings newMeetings
            )

        SetMeetingTitle s ->
            ( { model | meetingTitle = s }, Cmd.none )

        SetMeetingLength l ->
            ( { model | meetingLength = l }, Cmd.none )

        SelectUser s ->
            if model.selectedUser == Just s then
                ( model, Cmd.none )

            else
                ( { model | selectedUser = Just s }, loadUserWithEvents s )

        ToggleExpandParticipants ->
            ( { model | expandParticipants = not model.expandParticipants }, Cmd.none )

        ToggleUserMeeting u ->
            ( { model
                | meetingUsers =
                    if List.member u model.meetingUsers then
                        List.filter (\user -> user /= u) model.meetingUsers

                    else
                        u :: model.meetingUsers
              }
            , Cmd.none
            )

        ToggleExpandMeetings ->
            ( { model | expandMeetings = not model.expandMeetings }, Cmd.none )

        DeleteUser u ->
            let
                filteredUsers =
                    List.filter (\user -> user /= u) model.users

                filteredMeetingUsers =
                    List.filter (\user -> user /= u) model.meetingUsers

                updatedMeetings =
                    List.filter (\meeting -> List.length meeting.participantIds > 0) <|
                        List.map (\meeting -> { meeting | participantIds = List.filter (\id -> id /= u.id) meeting.participantIds }) model.meetings
            in
            ( { model
                | users = filteredUsers
                , selectedUser = Nothing
                , meetingUsers = filteredMeetingUsers
                , meetings = updatedMeetings
              }
            , Cmd.batch
                [ saveUsers filteredUsers
                , deleteUser u
                , destroyCalendar ()
                , saveMeetings updatedMeetings
                ]
            )

        NewUser ->
            ( { model
                | newUserName = ""
                , currentlyAddingUser = not model.currentlyAddingUser
              }
            , Cmd.none
            )

        UpdateUserName name ->
            ( { model | newUserName = name }, Cmd.none )

        LoadUsers jsValue ->
            case decodeValue decodeUsers jsValue of
                Ok data ->
                    ( { model | users = data }, Cmd.none )

                Err error ->
                    ( model, Cmd.none )

        LoadMeetings jsValue ->
            case decodeValue decodeMeetings jsValue of
                Ok data ->
                    ( { model | meetings = data }, Cmd.none )

                Err error ->
                    ( model, Cmd.none )

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
                            | users = newUser :: model.users
                            , newUserName = ""
                        }

                    else
                        model
            in
            ( newModel
            , Cmd.batch
                [ focusNewUserInput
                , saveUsers newModel.users
                ]
            )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.batch [ loadUsers LoadUsers, loadMeetings LoadMeetings ]



-- TASKS


focusNewUserInput : Cmd Msg
focusNewUserInput =
    Task.attempt (\_ -> NoOp) (Dom.focus "new-user-name-input")



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


port loadUsers : (Decode.Value -> msg) -> Sub msg


port loadMeetings : (Decode.Value -> msg) -> Sub msg


port saveUsers : List User -> Cmd msg


port saveMeetings : List Meeting -> Cmd msg


port destroyCalendar : () -> Cmd msg


port deleteUser : User -> Cmd msg


port loadUserWithEvents : User -> Cmd msg


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
