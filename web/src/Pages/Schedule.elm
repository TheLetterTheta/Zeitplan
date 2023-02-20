module Pages.Schedule exposing (Model, Msg, Participant, page)

import Browser.Dom as Dom exposing (setViewportOf)
import Calendar exposing (Event, Weekday, addEvent, dayString, dayToEvent, encodeEvent, isSaveMsg, stringToDay, timeRangeToDayString)
import Decoders exposing (AuthUser)
import Dict exposing (Dict)
import Effect exposing (Effect, fromCmd)
import FontAwesome as Icon
import FontAwesome.Attributes exposing (fa10x, spin)
import FontAwesome.Regular as Regular
import FontAwesome.Solid as Solid
import Gen.Params.Schedule exposing (Params)
import GraphQLApi.Mutation as Mutation
import GraphQLApi.Object
import GraphQLApi.Object.Calendar as ApiCalendar
import GraphQLApi.Object.Event as ApiEvent
import GraphQLApi.Object.Meeting as ApiMeeting
import GraphQLApi.Object.User as ApiUser
import GraphQLApi.Query as Query
import GraphQLApi.Scalar exposing (Id, Long)
import Graphql.Http
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.SelectionSet as SelectionSet exposing (SelectionSet, with)
import Html exposing (Html, a, aside, button, datalist, div, footer, form, h2, h3, header, input, label, li, option, p, section, select, span, text, ul)
import Html.Attributes exposing (checked, class, classList, disabled, for, href, id, list, placeholder, selected, type_, value)
import Html.Events exposing (onCheck, onClick, onInput, onSubmit, stopPropagationOn)
import Json.Decode as Decode
import Json.Encode as Encode
import Page
import Process
import RemoteData exposing (RemoteData)
import Request
import Set exposing (Set)
import Shared exposing (isError, saveKey)
import Task
import Time exposing (Posix)
import Validate exposing (Valid, Validator, fromValid, ifBlank, ifFalse, ifInvalidEmail, ifTrue, validate)
import View exposing (View, tooltip, zeitplanNav)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared _ =
    Page.protected.advanced
        (\user ->
            { init = init shared user
            , update = update user
            , view = view shared
            , subscriptions = subscriptions
            }
        )



-- INIT


type alias Participant =
    { events : List Event
    , blockedDays : List Weekday
    }


type alias Meeting =
    { title : String
    , duration : Int
    , participants : Set String
    }


encodeParticipant : Participant -> Encode.Value
encodeParticipant participant =
    Encode.object
        [ ( "events", Encode.list encodeEvent participant.events )
        ]


encodeMeeting : Meeting -> Encode.Value
encodeMeeting m =
    Encode.object
        [ ( "participants", Encode.set Encode.string m.participants )
        , ( "duration", Encode.int m.duration )
        , ( "title", Encode.string m.title )
        ]


type SliderState
    = AvailableCalendarSlider
    | ParticipantCalendarSlider
    | MeetingConfigurationSlider



-- GRAPHQL QUERIES


type alias GraphqlEvent =
    { start : Int
    , end : Int
    }


eventQuery : SelectionSet GraphqlEvent GraphQLApi.Object.Event
eventQuery =
    SelectionSet.succeed GraphqlEvent
        |> with ApiEvent.start
        |> with ApiEvent.end


type alias GraphqlUser =
    { credits : Int
    , events : List GraphqlEvent
    }


userQuery : SelectionSet GraphqlUser GraphQLApi.Object.User
userQuery =
    SelectionSet.succeed GraphqlUser
        |> with ApiUser.credits
        |> with (ApiUser.events eventQuery)


type alias GraphqlMeeting =
    { created : Long
    , duration : Int
    , participants : List Id
    , title : String
    }


meetingsQuery : SelectionSet GraphqlMeeting GraphQLApi.Object.Meeting
meetingsQuery =
    SelectionSet.succeed GraphqlMeeting
        |> with ApiMeeting.created
        |> with ApiMeeting.duration
        |> with ApiMeeting.participants
        |> with ApiMeeting.title


type alias GraphqlCalendar =
    { name : String
    , events : List GraphqlEvent
    , blockedDays : List String
    }


calendarsQuery : SelectionSet GraphqlCalendar GraphQLApi.Object.Calendar
calendarsQuery =
    SelectionSet.succeed GraphqlCalendar
        |> with ApiCalendar.name
        |> with (ApiCalendar.events eventQuery)
        |> with ApiCalendar.blockedDays


type alias InitialQuery =
    { user : GraphqlUser
    , calendars : List GraphqlCalendar
    , meetings : List GraphqlMeeting
    }


initialLoad : SelectionSet InitialQuery RootQuery
initialLoad =
    SelectionSet.succeed InitialQuery
        |> with (Query.user userQuery)
        |> with (Query.calendars calendarsQuery)
        |> with (Query.meetings meetingsQuery)


requestInitialLoad : String -> String -> Cmd Msg
requestInitialLoad url auth =
    initialLoad
        |> Graphql.Http.queryRequest url
        |> Graphql.Http.withHeader "Authorization" auth
        |> Graphql.Http.send (RemoteData.fromResult >> InitialDataLoaded)


type alias SaveAvailableResponse =
    { start : Int, end : Int }


saveAvailableEvents : List Event -> SelectionSet (List SaveAvailableResponse) RootMutation
saveAvailableEvents events =
    Mutation.saveEvents
        (List.map (\e -> { start = e.start, end = e.end }) events
            |> Mutation.SaveEventsRequiredArguments
        )
        (SelectionSet.succeed SaveAvailableResponse
            |> with ApiEvent.start
            |> with ApiEvent.end
        )


requestSaveAvailableEvents : String -> String -> List Event -> Cmd Msg
requestSaveAvailableEvents url auth events =
    saveAvailableEvents events
        |> Graphql.Http.mutationRequest url
        |> Graphql.Http.withHeader "Authorization" auth
        |> Graphql.Http.send (RemoteData.fromResult >> SaveAvailableCalendarSuccess)


type alias SaveParticipantResponse =
    { name : String }


saveParticipant : String -> Participant -> SelectionSet SaveParticipantResponse RootMutation
saveParticipant key participant =
    Mutation.saveCalendar
        (Mutation.SaveCalendarRequiredArguments
            key
            (List.map (\e -> { start = e.start, end = e.end }) participant.events)
            (List.map dayString participant.blockedDays)
        )
        (SelectionSet.succeed SaveParticipantResponse
            |> with ApiCalendar.name
        )


requestSaveParticipant : String -> String -> String -> Participant -> Cmd Msg
requestSaveParticipant url auth key participant =
    saveParticipant key participant
        |> Graphql.Http.mutationRequest url
        |> Graphql.Http.withHeader "Authorization" auth
        |> Graphql.Http.send (RemoteData.fromResult >> SaveParticipantSuccess)


type alias DeleteCalendarResponse =
    { name : String }


gqlDeleteParticipant : String -> SelectionSet (Maybe DeleteCalendarResponse) RootMutation
gqlDeleteParticipant key =
    Mutation.deleteCalendar
        (Mutation.DeleteCalendarRequiredArguments key)
        (SelectionSet.succeed DeleteCalendarResponse
            |> with ApiCalendar.name
        )


requestDeleteParticipant : String -> String -> String -> Cmd Msg
requestDeleteParticipant url auth key =
    gqlDeleteParticipant key
        |> Graphql.Http.mutationRequest url
        |> Graphql.Http.withHeader "Authorization" auth
        |> Graphql.Http.send (\_ -> NoOp)



-- VALIDATOR


participantNameValidator : Dict String a -> Validator String String
participantNameValidator dict =
    Validate.all
        [ ifBlank identity "Must enter a participant name"
        , ifTrue (\name -> Dict.member name dict) "Participant already exists!"
        ]


meetingTitleValidator : Validator String String
meetingTitleValidator =
    ifBlank identity "Must enter a title"



-- MODEL


type alias Model =
    { participants : Dict String Participant
    , participantCalendar : Calendar.Model
    , availableCalendar : Calendar.Model
    , selectedParticipant : Maybe String
    , newParticipantName : String
    , validatedParticipantName : Maybe (Result (List String) (Validate.Valid String))
    , slider : SliderState
    , initialLoad : RemoteData (Graphql.Http.Error InitialQuery) InitialQuery
    , credits : Int
    , endpoint : String
    , saveAvailableCalendarQueued : Bool
    , participantSaveQueue : Set String
    , meetingParticipants : Set String
    , participantSearch : String
    , meetingTitle : String
    , meetingTitleError : Maybe String
    , meetingDuration : Int
    , meetings : Dict Int Meeting
    , expandedMeetings : Set Int
    , deleteParticipant : Maybe { key : String, removedMeetings : Dict Int Meeting, affectedMeetings : Dict Int Meeting }
    }


init : Shared.Model -> AuthUser -> ( Model, Effect Msg )
init shared user =
    let
        ( availableCalendar, availableEffects ) =
            Calendar.init

        ( participantCalendar, participantEffects ) =
            Calendar.init
    in
    ( { participants = Dict.empty
      , participantCalendar = participantCalendar
      , availableCalendar = { availableCalendar | viewAllDayLine = False }
      , selectedParticipant = Nothing
      , newParticipantName = ""
      , validatedParticipantName = Nothing
      , slider = AvailableCalendarSlider
      , initialLoad = RemoteData.NotAsked
      , credits = 0
      , endpoint = shared.graphQlEndpoint
      , saveAvailableCalendarQueued = False
      , participantSaveQueue = Set.empty
      , meetingParticipants = Set.empty
      , participantSearch = ""
      , meetingTitle = ""
      , meetingTitleError = Nothing
      , meetingDuration = 2
      , meetings = Dict.empty
      , expandedMeetings = Set.empty
      , deleteParticipant = Nothing
      }
    , Effect.batch
        [ Effect.map (\a -> CalendarMsg ParticipantCalendar a) participantEffects
        , Effect.map (\a -> CalendarMsg ParticipantCalendar a) availableEffects
        , fromCmd <| Task.attempt (\_ -> NoOp) <| setViewportOf "participant-calendar" 0 310
        , fromCmd <| requestInitialLoad shared.graphQlEndpoint user.jwt
        ]
    )


mergeTimes : List Event -> List Event
mergeTimes times =
    times
        |> List.foldl
            (\event ->
                \list ->
                    let
                        ( _, events ) =
                            addEvent event list
                    in
                    events
            )
            []


subtractTimes : List Event -> List Event -> List Event
subtractTimes times subtract =
    subtract
        |> List.foldr
            (\remove ->
                \remaining ->
                    let
                        ( remainderEvents, conflictingEvents ) =
                            List.partition (\ev -> ev.end < (remove.start - 1) || ev.start > (1 + remove.end)) remaining

                        newConflictingEvents =
                            conflictingEvents
                                |> List.foldr
                                    (\ev ->
                                        \list ->
                                            if ev.start >= remove.start && ev.end <= remove.end then
                                                list

                                            else if ev.start < remove.start then
                                                { ev | end = remove.start - 1 } :: list

                                            else if ev.end > remove.end then
                                                { ev | start = remove.end + 1 } :: list

                                            else
                                                list
                                    )
                                    []
                    in
                    newConflictingEvents ++ remainderEvents
            )
            times



-- UPDATE


type Msg
    = SelectParticipant String
    | ChangeParticipantName String
    | SubmitNewParticipant
    | RequestDeleteParticipant String
    | DeleteParticipant String
    | SaveParticipantSuccess (RemoteData (Graphql.Http.Error SaveParticipantResponse) SaveParticipantResponse)
    | CalendarMsg Calendar Calendar.Msg
    | SaveAvailableCalendar
    | SharedMsg Shared.Msg
    | SaveAvailableCalendarSuccess (RemoteData (Graphql.Http.Error (List SaveAvailableResponse)) (List SaveAvailableResponse))
    | SetSliderState SliderState
    | InitialDataLoaded (RemoteData (Graphql.Http.Error InitialQuery) InitialQuery)
    | SaveParticipantQueue
    | SetSearchParticipant String
    | SelectMeetingParticipant String Bool
    | SelectFirstParticipant
    | SetMeetingTitle String
    | SetMeetingDuration String
    | CreateMeeting
    | FinishCreateMeeting Time.Posix
    | CloseDeleteModal
    | ExpandMeeting Bool Int
    | NoOp


update : AuthUser -> Msg -> Model -> ( Model, Effect Msg )
update user msg model =
    case msg of
        InitialDataLoaded remote ->
            case remote of
                RemoteData.Success data ->
                    let
                        toCalendarEvent =
                            \e ->
                                { start = e.start
                                , end = e.end
                                , dragging = False
                                , classList = []
                                }

                        availableCalendar =
                            model.availableCalendar

                        updatedAvailableCalendar =
                            { availableCalendar
                                | events = List.map toCalendarEvent data.user.events
                            }

                        credits =
                            data.user.credits

                        participants =
                            data.calendars
                                |> List.map
                                    (\cal ->
                                        ( cal.name
                                        , Participant
                                            (List.map toCalendarEvent cal.events)
                                            (List.map stringToDay cal.blockedDays)
                                        )
                                    )
                                |> Dict.fromList

                        selectedParticipant =
                            data.calendars |> List.map .name |> List.head

                        calendar : Calendar.Model
                        calendar =
                            model.participantCalendar

                        updatedCalendar : Calendar.Model
                        updatedCalendar =
                            case selectedParticipant of
                                Just key ->
                                    let
                                        ( blockedDays, events ) =
                                            Dict.get key participants
                                                |> Maybe.map (\p -> ( p.blockedDays, p.events ))
                                                |> Maybe.withDefault ( calendar.blockedDays, calendar.events )
                                    in
                                    { calendar | events = events, blockedDays = blockedDays }

                                Nothing ->
                                    calendar
                    in
                    ( { model
                        | availableCalendar = updatedAvailableCalendar
                        , participants = participants
                        , credits = credits
                        , selectedParticipant = selectedParticipant
                        , participantCalendar = updatedCalendar
                        , initialLoad = remote
                      }
                    , Effect.none
                    )

                _ ->
                    ( { model | initialLoad = remote }, Effect.none )

        SelectParticipant participantKey ->
            let
                calendar : Calendar.Model
                calendar =
                    model.participantCalendar

                ( blockedDays, events ) =
                    Dict.get participantKey model.participants
                        |> Maybe.map (\p -> ( p.blockedDays, p.events ))
                        |> Maybe.withDefault ( calendar.blockedDays, calendar.events )

                updatedCalendar : Calendar.Model
                updatedCalendar =
                    { calendar
                        | events = events
                        , blockedDays = blockedDays
                    }
            in
            ( { model
                | selectedParticipant = Just participantKey
                , participantCalendar = updatedCalendar
              }
            , Effect.none
            )

        RequestDeleteParticipant key ->
            let
                ( removedMeetings, restMeetings ) =
                    model.meetings
                        |> Dict.partition (\id -> \meeting -> meeting.participants == Set.singleton key)

                affectedMeetings =
                    restMeetings
                        |> Dict.filter (\id -> \meeting -> Set.member key meeting.participants)
            in
            ( { model
                | deleteParticipant =
                    Just
                        { key = key
                        , removedMeetings = removedMeetings
                        , affectedMeetings = affectedMeetings
                        }
              }
            , Effect.none
            )

        DeleteParticipant key ->
            let
                deleteParticipant =
                    Dict.get key model.participants

                newDict =
                    Dict.remove key model.participants

                nextDefault =
                    Dict.toList newDict
                        |> List.head

                newMeetings =
                    model.meetings
                        |> Dict.filter (\id -> \meeting -> meeting.participants /= Set.singleton key)
                        |> Dict.map
                            (\id ->
                                \meeting ->
                                    { meeting | participants = Set.remove key meeting.participants }
                            )

                participantCalendar =
                    model.participantCalendar

                ( newEvents, newBlocked ) =
                    nextDefault
                        |> Maybe.map (\( _, v ) -> ( v.events, v.blockedDays ))
                        |> Maybe.withDefault ( [], [] )

                updatedCalendar : Calendar.Model
                updatedCalendar =
                    { participantCalendar
                        | events = newEvents
                        , blockedDays = newBlocked
                    }

                selectedParticipants =
                    Set.remove key model.meetingParticipants
            in
            ( { model
                | selectedParticipant = nextDefault |> Maybe.map (\( k, _ ) -> k)
                , participants = newDict
                , participantCalendar = updatedCalendar
                , meetingParticipants = selectedParticipants
                , meetings = newMeetings
                , deleteParticipant = Nothing
              }
              {--TODO: Delete meetings, and relevant participants also --}
            , Effect.fromCmd <| requestDeleteParticipant model.endpoint user.jwt key
            )

        SaveParticipantQueue ->
            let
                requests =
                    model.participantSaveQueue
                        |> Set.toList
                        |> List.map
                            (\key ->
                                Dict.get key model.participants
                                    |> Maybe.map
                                        (\participant ->
                                            Effect.fromCmd <|
                                                requestSaveParticipant model.endpoint user.jwt key participant
                                        )
                                    |> Maybe.withDefault Effect.none
                            )
                        |> Effect.batch
            in
            ( { model | participantSaveQueue = Set.empty }, requests )

        ChangeParticipantName name ->
            let
                validatedName : Result (List String) (Valid String)
                validatedName =
                    validate (participantNameValidator model.participants) name
            in
            ( { model
                | validatedParticipantName = Just validatedName
                , newParticipantName = name
              }
            , Effect.none
            )

        SubmitNewParticipant ->
            case model.validatedParticipantName |> Maybe.map (Result.map fromValid) of
                Just (Ok name) ->
                    let
                        newParticipant =
                            Participant [] []
                    in
                    ( { model
                        | newParticipantName = ""
                        , validatedParticipantName = Nothing
                        , participants = Dict.insert name newParticipant model.participants
                      }
                    , Effect.fromCmd <|
                        requestSaveParticipant model.endpoint user.jwt name newParticipant
                    )

                _ ->
                    ( model, Effect.none )

        SaveParticipantSuccess _ ->
            ( model, Effect.none )

        SaveAvailableCalendar ->
            ( { model | saveAvailableCalendarQueued = False }
            , Effect.fromCmd <|
                requestSaveAvailableEvents model.endpoint user.jwt model.availableCalendar.events
            )

        SaveAvailableCalendarSuccess _ ->
            ( model, Effect.none )

        CalendarMsg calendar calendarMsg ->
            case calendar of
                AvailableCalendar ->
                    let
                        ( newCalendar, effects ) =
                            Calendar.update calendarMsg model.availableCalendar

                        ( queue, effect ) =
                            if
                                isSaveMsg calendarMsg
                                    && not model.saveAvailableCalendarQueued
                            then
                                ( True
                                , Process.sleep 6000
                                    |> Task.perform (\_ -> SaveAvailableCalendar)
                                    |> Effect.fromCmd
                                )

                            else
                                ( model.saveAvailableCalendarQueued, Effect.none )
                    in
                    ( { model | availableCalendar = newCalendar, saveAvailableCalendarQueued = queue }
                    , Effect.batch
                        [ Effect.map (\a -> CalendarMsg AvailableCalendar a) effects
                        , effect
                        ]
                    )

                ParticipantCalendar ->
                    let
                        ( newCalendar, effects ) =
                            Calendar.update calendarMsg model.participantCalendar

                        ( participants, queue, effect ) =
                            case model.selectedParticipant of
                                Just key ->
                                    ( Dict.update key
                                        (Maybe.map
                                            (\participant ->
                                                { participant | events = newCalendar.events, blockedDays = newCalendar.blockedDays }
                                            )
                                        )
                                        model.participants
                                    , if isSaveMsg calendarMsg then
                                        Set.insert key model.participantSaveQueue

                                      else
                                        model.participantSaveQueue
                                    , if isSaveMsg calendarMsg && Set.isEmpty model.participantSaveQueue then
                                        Process.sleep 6000
                                            |> Task.perform (\_ -> SaveParticipantQueue)
                                            |> Effect.fromCmd

                                      else
                                        Effect.none
                                    )

                                Nothing ->
                                    ( model.participants, model.participantSaveQueue, Effect.none )
                    in
                    ( { model
                        | participants = participants
                        , participantCalendar = newCalendar
                        , participantSaveQueue = queue
                      }
                    , Effect.batch
                        [ Effect.map (\a -> CalendarMsg ParticipantCalendar a) effects
                        , effect
                        ]
                    )

        SetSliderState s ->
            case s of
                ParticipantCalendarSlider ->
                    ( { model | slider = s }, Effect.fromCmd <| Task.attempt (\_ -> NoOp) (Dom.focus "participant-name-input") )

                _ ->
                    ( { model | slider = s }, Effect.none )

        SharedMsg sharedMsg ->
            ( model, Effect.fromShared sharedMsg )

        SetSearchParticipant name ->
            ( { model | participantSearch = name }, Effect.none )

        SelectMeetingParticipant name isAdd ->
            let
                participants =
                    if isAdd then
                        Set.insert name model.meetingParticipants

                    else
                        Set.remove name model.meetingParticipants
            in
            ( { model | meetingParticipants = participants }, Effect.none )

        SelectFirstParticipant ->
            let
                meetingParticipants =
                    Dict.keys model.participants
                        |> List.filter
                            (if String.isEmpty model.participantSearch then
                                always True

                             else
                                String.toUpper >> String.contains (String.toUpper model.participantSearch)
                            )
                        |> List.head
                        |> Maybe.map
                            (\key ->
                                if Set.member key model.meetingParticipants then
                                    Set.remove key model.meetingParticipants

                                else
                                    Set.insert key model.meetingParticipants
                            )
                        |> Maybe.withDefault model.meetingParticipants
            in
            ( { model | meetingParticipants = meetingParticipants, participantSearch = "" }, Effect.none )

        CreateMeeting ->
            -- TODO: Add validation and api call here
            ( model, Effect.fromCmd <| Task.perform FinishCreateMeeting <| Time.now )

        FinishCreateMeeting time ->
            let
                id =
                    Time.posixToMillis time
            in
            case validate meetingTitleValidator model.meetingTitle of
                Ok valid ->
                    ( { model
                        | meetings =
                            Dict.insert id
                                { title = Validate.fromValid valid, duration = model.meetingDuration, participants = model.meetingParticipants }
                                model.meetings
                      }
                    , Effect.none
                    )

                Err _ ->
                    ( model, Effect.none )

        SetMeetingTitle title ->
            case validate meetingTitleValidator title |> Result.mapError List.head of
                Ok valid ->
                    ( { model | meetingTitle = title, meetingTitleError = Nothing }, Effect.none )

                Err result ->
                    ( { model | meetingTitle = title, meetingTitleError = result }, Effect.none )

        SetMeetingDuration duration ->
            ( { model | meetingDuration = String.toInt duration |> Maybe.withDefault 0 }, Effect.none )

        CloseDeleteModal ->
            ( { model | deleteParticipant = Nothing }, Effect.none )

        ExpandMeeting expand id ->
            ( { model
                | expandedMeetings =
                    if expand then
                        Set.insert id model.expandedMeetings

                    else
                        Set.remove id model.expandedMeetings
              }
            , Effect.none
            )

        NoOp ->
            ( model, Effect.none )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none



-- VIEW


type Calendar
    = ParticipantCalendar
    | AvailableCalendar


participantList : Model -> Html Msg
participantList model =
    ul [ class "menu-list" ]
        (model.participants
            |> Dict.toList
            |> List.map
                (\( key, participant ) ->
                    li
                        [ class "participant-list-item"
                        , onClick <| SelectParticipant key
                        ]
                        [ a
                            [ href "#"
                            , class "participant-name"
                            , classList [ ( "is-active", model.selectedParticipant == Just key ) ]
                            ]
                            [ text key
                            , if model.selectedParticipant == Just key then
                                button [ class "delete", stopPropagationOn "click" <| Decode.succeed ( RequestDeleteParticipant key, True ) ] []

                              else
                                text ""
                            ]
                        ]
                )
        )


createParticipantForm : Model -> Html Msg
createParticipantForm model =
    form [ class "form participant-form", onSubmit SubmitNewParticipant ]
        [ label [ class "label", for "participant-name-input" ] [ text "Add Participant" ]
        , div [ class "field has-addons" ]
            [ div [ class "control" ]
                [ input
                    [ class "input"
                    , id "participant-name-input"
                    , classList
                        [ ( "is-danger"
                          , Maybe.map isError model.validatedParticipantName |> Maybe.withDefault False
                          )
                        ]
                    , type_ "text"
                    , value model.newParticipantName
                    , placeholder "Name"
                    , onInput ChangeParticipantName
                    ]
                    []
                ]
            , div [ class "control" ]
                [ button
                    [ class "button is-success", type_ "submit" ]
                    [ Icon.view Solid.add ]
                ]
            ]
        ]


sliderView : Model -> Html Msg
sliderView model =
    case model.slider of
        AvailableCalendarSlider ->
            div [ class "availability" ]
                [ div [ id "available-calendar" ]
                    [ Calendar.view model.availableCalendar |> Html.map (CalendarMsg AvailableCalendar) ]
                ]

        ParticipantCalendarSlider ->
            div
                [ class "participants"
                , classList [ ( "is-clipped", model.deleteParticipant /= Nothing ) ]
                ]
                [ case model.deleteParticipant of
                    Just { key, affectedMeetings, removedMeetings } ->
                        div [ class "modal is-active" ]
                            [ div [ class "modal-background" ] []
                            , div [ class "modal-card" ]
                                [ header [ class "modal-card-head" ]
                                    [ h3 [ class "modal-card-title" ] [ text <| "Delete " ++ key ++ "?" ]
                                    , button [ class "delete", onClick CloseDeleteModal ] []
                                    ]
                                , section [ class "modal-card-body" ]
                                    [ div [ class "content" ]
                                        [ p [] [ text <| "Are you sure you want to delete " ++ key ]
                                        ]
                                    ]
                                , footer [ class "modal-card-foot" ]
                                    [ button [ class "button is-success", onClick <| DeleteParticipant key ] [ text "Confirm" ]
                                    , button [ class "button is-danger", onClick CloseDeleteModal ] [ text "Cancel" ]
                                    ]
                                ]
                            ]

                    Nothing ->
                        text ""
                , div [ class "participant-list-container" ]
                    [ aside [ class "participant-list menu" ]
                        [ p [ class "menu-label" ] [ text "Participants" ]
                        , participantList model
                        ]
                    , createParticipantForm model
                    ]
                , div [ id "participant-calendar" ]
                    [ div
                        [ classList [ ( "loading ignore-pointer-events", model.selectedParticipant == Nothing ) ] ]
                        [ Calendar.view model.participantCalendar |> Html.map (CalendarMsg ParticipantCalendar) ]
                    ]
                ]

        MeetingConfigurationSlider ->
            let
                canBeScheduled =
                    model.meetingParticipants
                        |> Set.toList
                        |> List.map
                            (\key ->
                                Dict.get key model.participants
                                    |> Maybe.map
                                        (\participant ->
                                            participant.events
                                                ++ (participant.blockedDays |> List.map dayToEvent)
                                        )
                                    |> Maybe.withDefault []
                            )
                        |> List.concat
                        |> mergeTimes
                        |> subtractTimes (model.availableCalendar.events ++ List.map dayToEvent model.availableCalendar.blockedDays)
                        |> List.filter (\event -> (event.end - event.start) + 1 >= model.meetingDuration)
                        |> List.isEmpty
                        |> not
            in
            div [ class "columns meeting-configuration" ] <|
                [ aside [ class "column is-one-third aside-form" ]
                    [ div [ class "panel is-info meeting-panel" ] <|
                        h2
                            [ class "panel-heading" ]
                            [ text "Select Participants"
                            , span [ class "ml-2" ]
                                [ text <|
                                    if Set.isEmpty model.meetingParticipants then
                                        ""

                                    else
                                        "(" ++ (String.fromInt <| Set.size model.meetingParticipants) ++ ")"
                                ]
                            ]
                            :: div [ class "panel-block" ]
                                [ p [ class "control has-icons-left" ]
                                    [ form [ onSubmit SelectFirstParticipant ]
                                        [ input
                                            [ class "input"
                                            , type_ "search"
                                            , value model.participantSearch
                                            , placeholder "Search"
                                            , onInput SetSearchParticipant

                                            -- , list "participant-data-list"
                                            ]
                                            []
                                        , span [ class "icon is-left" ] [ Icon.view Solid.search ]
                                        ]
                                    ]
                                ]
                            {--
                            :: datalist [ id "participant-data-list" ]
                                (Dict.keys model.participants
                                    |> List.map (\name -> option [ value name ] [])
                                )
                            --}
                            :: (Dict.keys model.participants
                                    |> List.filter
                                        (if String.isEmpty model.participantSearch then
                                            always True

                                         else
                                            String.toUpper >> String.contains (String.toUpper model.participantSearch)
                                        )
                                    |> List.indexedMap
                                        (\index ->
                                            \name ->
                                                label
                                                    [ class "panel-block"
                                                    , classList
                                                        [ ( "is-active", Set.member name model.meetingParticipants )
                                                        , ( "highlighted", index == 0 )
                                                        ]
                                                    ]
                                                    [ input
                                                        [ type_ "checkbox"
                                                        , checked <| Set.member name model.meetingParticipants
                                                        , onCheck <| SelectMeetingParticipant name
                                                        ]
                                                        []
                                                    , text name
                                                    ]
                                        )
                               )
                    , form [ class "meeting-form", onSubmit CreateMeeting ]
                        [ div [ class "field" ]
                            [ label [ class "label" ] [ text "Title" ]
                            , input
                                [ class "input"
                                , classList [ ( "is-danger", model.meetingTitleError /= Nothing ) ]
                                , type_ "text"
                                , value model.meetingTitle
                                , onInput SetMeetingTitle
                                ]
                                []
                            , case model.meetingTitleError of
                                Just error ->
                                    p [ class "help is-danger" ] [ text error ]

                                _ ->
                                    text ""
                            ]
                        , div [ class "field" ]
                            [ label [ class "label" ] [ text "Duration" ]
                            , div [ class "control has-icons-left" ]
                                [ div [ class "select is-rounded is-medium" ]
                                    [ select [ onInput SetMeetingDuration ]
                                        [ option [ value "1", selected <| model.meetingDuration == 1 ] [ text "30 min" ]
                                        , option [ value "2", selected <| model.meetingDuration == 2 ] [ text "1 hour" ]
                                        , option [ value "3", selected <| model.meetingDuration == 3 ] [ text "90 min" ]
                                        , option [ value "4", selected <| model.meetingDuration == 4 ] [ text "2 hours" ]
                                        ]
                                    ]
                                , div [ class "icon is-small is-left" ]
                                    [ Icon.view Solid.clock ]
                                ]
                            ]
                        , div [ class "field" ]
                            [ div [ class "control" ]
                                [ button
                                    [ class "button is-success is-medium is-fullwidth"
                                    , disabled (Set.isEmpty model.meetingParticipants || String.isEmpty model.meetingTitle)
                                    ]
                                    [ span [] [ text "Create Meeting" ]
                                    , span
                                        [ tooltip <|
                                            "This meeting "
                                                ++ (if canBeScheduled then
                                                        "can"

                                                    else
                                                        "can not"
                                                   )
                                                ++ " be scheduled"
                                        , class "icon has-tooltip-arrow has-tooltip-bottom"
                                        , classList [ ( "is-danger", not canBeScheduled ) ]
                                        ]
                                        [ Icon.view <|
                                            if canBeScheduled then
                                                Solid.check

                                            else
                                                Regular.circleXmark
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]
                , div [ class "column meeting-list" ]
                    [ div [ class "columns is-multiline" ]
                        (model.meetings
                            |> Dict.map
                                (\id ->
                                    \meeting ->
                                        let
                                            meetingTimes =
                                                meeting.participants
                                                    |> Set.toList
                                                    |> List.map
                                                        (\key ->
                                                            Dict.get key model.participants
                                                                |> Maybe.map
                                                                    (\participant ->
                                                                        participant.events
                                                                            ++ (participant.blockedDays |> List.map dayToEvent)
                                                                    )
                                                                |> Maybe.withDefault []
                                                        )
                                                    |> List.concat
                                                    |> mergeTimes
                                                    |> subtractTimes (model.availableCalendar.events ++ List.map dayToEvent model.availableCalendar.blockedDays)
                                                    |> List.filter (\event -> (event.end - event.start) + 1 >= model.meetingDuration)

                                            meetingExpanded =
                                                Set.member id model.expandedMeetings
                                        in
                                        div
                                            [ class "column meeting-item is-4 panel is-primary"
                                            , classList [ ( "is-danger", List.isEmpty meetingTimes ) ]
                                            ]
                                        <|
                                            [ h2 [ class "panel-heading" ]
                                                [ span [] [ text meeting.title ]
                                                , span [ class "ml-3" ]
                                                    [ text <|
                                                        "("
                                                            ++ (case meeting.duration of
                                                                    1 ->
                                                                        "30 min"

                                                                    2 ->
                                                                        "1 hour"

                                                                    3 ->
                                                                        "90 min"

                                                                    4 ->
                                                                        "2 hours"

                                                                    other ->
                                                                        String.fromInt (other * 30) ++ " min."
                                                               )
                                                            ++ ")"
                                                    ]
                                                ]
                                            , div
                                                [ class "panel-block" ]
                                                [ div
                                                    [ class "tags are-medium" ]
                                                  <|
                                                    List.map (\name -> span [ class "tag is-info" ] [ text name ]) <|
                                                        Set.toList meeting.participants
                                                ]
                                            ]
                                                ++ (meetingTimes
                                                        |> List.sortBy .start
                                                        |> (\list ->
                                                                if meetingExpanded then
                                                                    list

                                                                else
                                                                    List.take 3 list
                                                           )
                                                        |> List.map (\timeblock -> timeRangeToDayString timeblock.start timeblock.end)
                                                        |> List.map
                                                            (\timeblock ->
                                                                a
                                                                    [ class "panel-block ignore-pointer-events" ]
                                                                    [ span [ class "panel-icon" ] [ Icon.view Solid.clock ]
                                                                    , text timeblock
                                                                    ]
                                                            )
                                                   )
                                                ++ (if List.isEmpty meetingTimes then
                                                        [ a [ class "panel-block ignore-pointer-events" ]
                                                            [ text "This meeting can not be scheduled!" ]
                                                        ]

                                                    else if List.length meetingTimes > 3 then
                                                        [ div [ class "panel-block" ]
                                                            [ button
                                                                [ onClick <| ExpandMeeting (not meetingExpanded) id
                                                                , class "button is-small is-outlined is-fullwidth"
                                                                ]
                                                                [ text <|
                                                                    if meetingExpanded then
                                                                        "Show Less"

                                                                    else
                                                                        "Show More"
                                                                ]
                                                            ]
                                                        ]

                                                    else
                                                        []
                                                   )
                                )
                            |> Dict.values
                        )
                    ]
                ]


view : Shared.Model -> Model -> View Msg
view shared model =
    View "Zeitplan - Schedule"
        [ zeitplanNav
            { logo = shared.logo
            , shared = shared
            }
            |> Html.map SharedMsg
        , if model.initialLoad == RemoteData.NotAsked || model.initialLoad == RemoteData.Loading then
            div
                [ class "loading-container" ]
                [ Icon.view <| Icon.styled [ spin, fa10x ] Solid.spinner
                , p [] [ text "Please wait while we fetch your information" ]
                ]

          else
            div [ class "container is-fullhd" ]
                [ div [ class "box mt-2" ]
                    [ ul [ class "steps is-centered has-content-centered" ]
                        [ li
                            [ tooltip "Add times for your meetings"
                            , class "steps-segment has-tooltip-bottom has-tooltip-multiline"
                            , classList [ ( "is-active", model.slider == AvailableCalendarSlider ) ]
                            ]
                            [ a
                                [ href "#"
                                , class "has-text-dark"
                                , onClick <| SetSliderState AvailableCalendarSlider
                                ]
                                [ span [ class "steps-marker icon is-small" ] [ Icon.view Solid.calendarWeek ]
                                , div [ class "steps-content" ] [ text "Set Available Times" ]
                                ]
                            ]
                        , li
                            [ tooltip "Add people to meet with - and when they can't meet"
                            , class "steps-segment has-tooltip-bottom has-tooltip-multiline"
                            , classList
                                [ ( "is-active", model.slider == ParticipantCalendarSlider )
                                , ( "ignore-pointer-events", List.isEmpty model.availableCalendar.events )
                                ]
                            ]
                            [ a
                                [ href "#"
                                , class "has-text-dark"
                                , onClick <| SetSliderState ParticipantCalendarSlider
                                ]
                                [ span [ class "steps-marker icon is-small" ] [ Icon.view Solid.user ]
                                , div [ class "steps-content" ]
                                    [ text "Add Participants"
                                    , span [ class "ml-2" ]
                                        [ text <|
                                            if Dict.isEmpty model.participants then
                                                ""

                                            else
                                                "(" ++ (String.fromInt <| Dict.size model.participants) ++ ")"
                                        ]
                                    ]
                                ]
                            ]
                        , li
                            [ tooltip "Setup meetings with your participants"
                            , class "steps-segment has-tooltip-bottom has-tooltip-multiline"
                            , classList
                                [ ( "is-active", model.slider == MeetingConfigurationSlider )
                                , ( "ignore-pointer-events", Dict.isEmpty model.participants )
                                ]
                            ]
                            [ a
                                [ href "#"
                                , class "has-text-dark"
                                , onClick <| SetSliderState MeetingConfigurationSlider
                                ]
                                [ span [ class "steps-marker icon is-small" ] [ Icon.view Solid.calendarPlus ]
                                , div [ class "steps-content" ]
                                    [ text "Create Meetings"
                                    , span [ class "ml-2" ]
                                        [ text <|
                                            if Dict.isEmpty model.meetings then
                                                ""

                                            else
                                                "(" ++ (String.fromInt <| Dict.size model.meetings) ++ ")"
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    , sliderView model
                    ]
                ]
        , View.footer
        ]
