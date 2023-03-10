module Pages.Schedule exposing (Model, Msg, Participant, page)

import Browser.Dom as Dom exposing (setViewportOf)
import Calendar exposing (Event, Weekday, addEvent, dayString, dayToEvent, encodeEvent, isSaveMsg, stringToDay, timeRangeToDayString, timeToDayString)
import Decoders exposing (AuthUser)
import Dict exposing (Dict)
import Dict.Extra exposing (groupBy)
import Effect exposing (Effect, fromCmd)
import FontAwesome as Icon
import FontAwesome.Attributes exposing (fa10x, spin)
import FontAwesome.Regular as Regular
import FontAwesome.Solid as Solid
import Gen.Params.Schedule exposing (Params)
import Graphql.Http
import Graphql.Operation exposing (RootMutation, RootQuery)
import Graphql.OptionalArgument exposing (OptionalArgument(..))
import Graphql.SelectionSet as SelectionSet exposing (SelectionSet, with)
import Html exposing (Html, a, aside, button, code, datalist, div, figure, footer, form, h2, h3, h4, header, img, input, label, li, option, p, section, select, span, table, tbody, td, text, tfoot, th, thead, tr, ul)
import Html.Attributes exposing (attribute, checked, class, classList, disabled, for, href, id, list, name, placeholder, selected, style, type_, value)
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
import Time exposing (Posix, Zone)
import Validate exposing (Valid, Validator, fromValid, ifBlank, ifFalse, ifInvalidEmail, ifTrue, validate)
import View exposing (View, tooltip, zeitplanNav)
import ZeitplanApi.Mutation as Mutation
import ZeitplanApi.Object
import ZeitplanApi.Object.Calendar as ApiCalendar
import ZeitplanApi.Object.Event as ApiEvent
import ZeitplanApi.Object.Meeting as ApiMeeting
import ZeitplanApi.Object.PaymentIntent as ApiCheckout
import ZeitplanApi.Object.ScheduleMeetingResult as ApiScheduleMeetingResult
import ZeitplanApi.Object.ScheduleResponse as ApiScheduleResponse
import ZeitplanApi.Object.Schedules as ApiSchedules
import ZeitplanApi.Object.User as ApiUser
import ZeitplanApi.Query as Query
import ZeitplanApi.Scalar exposing (Id, Long(..))


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
    | ScheduleMeetingsSlider


type PurchaseModalTab
    = SelectCredits
    | Checkout



-- GRAPHQL QUERIES


type alias GraphqlEvent =
    { start : Int
    , end : Int
    }


eventQuery : SelectionSet GraphqlEvent ZeitplanApi.Object.Event
eventQuery =
    SelectionSet.succeed GraphqlEvent
        |> with ApiEvent.start
        |> with ApiEvent.end


type alias GraphqlUser =
    { credits : Int
    , events : List GraphqlEvent
    }


userQuery : SelectionSet GraphqlUser ZeitplanApi.Object.User
userQuery =
    SelectionSet.succeed GraphqlUser
        |> with ApiUser.credits
        |> with (ApiUser.events eventQuery)


type alias GraphqlMeeting =
    { created : Long
    , duration : Int
    , participants : List String
    , title : String
    }


meetingsQuery : SelectionSet GraphqlMeeting ZeitplanApi.Object.Meeting
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


calendarsQuery : SelectionSet GraphqlCalendar ZeitplanApi.Object.Calendar
calendarsQuery =
    SelectionSet.succeed GraphqlCalendar
        |> with ApiCalendar.name
        |> with (ApiCalendar.events eventQuery)
        |> with ApiCalendar.blockedDays


type alias ScheduleResult =
    { id : String
    , time : GraphqlEvent
    }


responseQuery : SelectionSet ScheduleResult ZeitplanApi.Object.ScheduleMeetingResult
responseQuery =
    SelectionSet.succeed ScheduleResult
        |> with ApiScheduleMeetingResult.id
        |> with (ApiScheduleMeetingResult.time eventQuery)


type alias Schedule =
    { results : Maybe (List ScheduleResult)
    , failed : Maybe (List String)
    , error : Maybe String
    , created : Long
    }


dataQuery : SelectionSet Schedule ZeitplanApi.Object.ScheduleResponse
dataQuery =
    SelectionSet.succeed Schedule
        |> with (ApiScheduleResponse.results responseQuery)
        |> with ApiScheduleResponse.failed
        |> with ApiScheduleResponse.error
        |> with ApiScheduleResponse.created


type alias Schedules =
    { data : List Schedule
    , nextToken : Maybe String
    }


schedulesQuery : SelectionSet Schedules ZeitplanApi.Object.Schedules
schedulesQuery =
    SelectionSet.succeed Schedules
        |> with (ApiSchedules.data dataQuery)
        |> with ApiSchedules.nextToken


type alias InitialQuery =
    { user : GraphqlUser
    , calendars : List GraphqlCalendar
    , meetings : List GraphqlMeeting
    , schedules : Maybe Schedules
    }


initialLoad : SelectionSet InitialQuery RootQuery
initialLoad =
    SelectionSet.succeed InitialQuery
        |> with (Query.user userQuery)
        |> with (Query.calendars calendarsQuery)
        |> with (Query.meetings meetingsQuery)
        |> with (Query.schedules (always { nextToken = Absent }) { limit = 5 } schedulesQuery)


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


gqlDeleteParticipant : String -> SelectionSet (Maybe ()) RootMutation
gqlDeleteParticipant key =
    Mutation.deleteCalendar
        (Mutation.DeleteCalendarRequiredArguments key)
        SelectionSet.empty


requestDeleteParticipant : String -> String -> String -> Cmd Msg
requestDeleteParticipant url auth key =
    gqlDeleteParticipant key
        |> Graphql.Http.mutationRequest url
        |> Graphql.Http.withHeader "Authorization" auth
        |> Graphql.Http.send (\_ -> NoOp)


type alias SaveMeetingResponse =
    { created : Long }


createMeeting : Int -> Meeting -> SelectionSet () RootMutation
createMeeting created meeting =
    Mutation.saveMeeting
        (\_ -> Mutation.SaveMeetingOptionalArguments (Present <| ZeitplanApi.Scalar.Long <| String.fromInt created))
        (Mutation.SaveMeetingRequiredArguments
            (Set.toList meeting.participants)
            meeting.title
            meeting.duration
        )
        SelectionSet.empty


requestCreateMeeting : String -> String -> Int -> Meeting -> Cmd Msg
requestCreateMeeting url auth created meeting =
    createMeeting created meeting
        |> Graphql.Http.mutationRequest url
        |> Graphql.Http.withHeader "Authorization" auth
        |> Graphql.Http.send (\_ -> NoOp)


deleteMeeting : Int -> SelectionSet (Maybe SaveMeetingResponse) RootMutation
deleteMeeting created =
    Mutation.deleteMeeting
        { created = Long (String.fromInt created) }
        (SelectionSet.succeed SaveMeetingResponse
            |> with ApiMeeting.created
        )


requestDeleteMeeting : String -> String -> Int -> Cmd Msg
requestDeleteMeeting url auth created =
    deleteMeeting created
        |> Graphql.Http.mutationRequest url
        |> Graphql.Http.withHeader "Authorization" auth
        |> Graphql.Http.send (\_ -> NoOp)


type alias BeginCheckoutResponse =
    { amount : Maybe Int
    , clientSecret : String
    , orderId : Id
    }


beginCheckout : Int -> SelectionSet BeginCheckoutResponse RootMutation
beginCheckout credits =
    Mutation.beginCheckout { credits = credits }
        (SelectionSet.succeed BeginCheckoutResponse
            |> with ApiCheckout.amount
            |> with ApiCheckout.clientSecret
            |> with ApiCheckout.orderId
        )


requestBeginCheckout : String -> String -> Int -> Cmd Msg
requestBeginCheckout url auth credits =
    beginCheckout credits
        |> Graphql.Http.mutationRequest url
        |> Graphql.Http.withHeader "Authorization" auth
        |> Graphql.Http.send (RemoteData.fromResult >> CheckoutIntentResponse)



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


formatTime : Zone -> Time.Posix -> String
formatTime zone time =
    let
        day =
            case Time.toWeekday zone time of
                Time.Mon ->
                    "Monday"

                Time.Tue ->
                    "Tuesday"

                Time.Wed ->
                    "Wednesday"

                Time.Thu ->
                    "Thursday"

                Time.Fri ->
                    "Friday"

                Time.Sat ->
                    "Saturday"

                Time.Sun ->
                    "Sunday"

        zeroHour =
            Time.toHour zone time

        meridian =
            if zeroHour < 12 then
                "AM"

            else
                "PM"

        hour =
            case modBy 12 zeroHour of
                0 ->
                    "12"

                e ->
                    String.fromInt e

        minute =
            String.padLeft 2 '0' <| String.fromInt <| Time.toMinute zone time

        second =
            String.padLeft 2 '0' <| String.fromInt <| Time.toSecond zone time
    in
    day ++ " " ++ hour ++ ":" ++ minute ++ ":" ++ second ++ " " ++ meridian

durationToString : Int -> String
durationToString duration =
    case duration of
        0 -> "0 min"
        1 ->
            "30 min"

        2 ->
            "1 hour"

        3 ->
            "90 min"

        4 ->
            "2 hours"

        other ->
            let
                hours = String.fromInt (other // 2) ++ " hours"
                minutes = if modBy 2 other == 1 then
                              " 30 min"
                            else
                                ""
            in
            hours ++ minutes

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
    , purchaseModalActive : Bool
    , purchaseModalTab : PurchaseModalTab
    , checkoutIntent : Maybe String
    , checkoutCredits : Int
    , schedules : List Schedule
    , schedulesNextToken : Maybe String
    , viewSchedule : Maybe (List ScheduleResult)
    , zone : Maybe Zone
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
      , purchaseModalActive = False
      , purchaseModalTab = SelectCredits
      , checkoutIntent = Nothing
      , checkoutCredits = 5
      , schedules = []
      , schedulesNextToken = Nothing
      , viewSchedule = Nothing
      , zone = Nothing
      }
    , Effect.batch
        [ Effect.map (\a -> CalendarMsg ParticipantCalendar a) participantEffects
        , Effect.map (\a -> CalendarMsg ParticipantCalendar a) availableEffects
        , fromCmd <| Task.attempt (\_ -> NoOp) <| setViewportOf "participant-calendar" 0 310
        , fromCmd <| requestInitialLoad shared.graphQlEndpoint user.jwt
        , fromCmd <| Task.perform GetCurrentTimezone <| Time.here
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
    | InitialDataLoaded (RemoteData (Graphql.Http.Error InitialQuery) InitialQuery)
    | GetCurrentTimezone Zone
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
    | DeleteMeeting Int
    | TogglePurchaseModal
    | SetPurchaseTab PurchaseModalTab
    | CheckoutIntentResponse (RemoteData (Graphql.Http.Error BeginCheckoutResponse) BeginCheckoutResponse)
    | ViewScheduleResults (List ScheduleResult)
    | CloseScheduleModal
    | SetPurchaseCreditsAmount String
    | NoOp


update : AuthUser -> Msg -> Model -> ( Model, Effect Msg )
update user msg model =
    case msg of
        GetCurrentTimezone zone ->
            ( { model | zone = Just zone }, Effect.none )

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

                        meetings : Dict Int Meeting
                        meetings =
                            data.meetings
                                |> List.map
                                    (\meeting ->
                                        let
                                            created =
                                                case meeting.created of
                                                    Long val ->
                                                        String.toInt val |> Maybe.withDefault 0
                                        in
                                        ( created, Meeting meeting.title meeting.duration (Set.fromList meeting.participants) )
                                    )
                                |> Dict.fromList

                        nextToken : Maybe String
                        nextToken =
                            data.schedules |> Maybe.map .nextToken |> Maybe.withDefault Nothing

                        schedules : List Schedule
                        schedules =
                            data.schedules
                                |> Maybe.map .data
                                |> Maybe.withDefault []
                    in
                    ( { model
                        | availableCalendar = updatedAvailableCalendar
                        , participants = participants
                        , credits = credits
                        , selectedParticipant = selectedParticipant
                        , participantCalendar = updatedCalendar
                        , meetings = meetings
                        , schedules = schedules
                        , schedulesNextToken = nextToken
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
                    if isAdd && Set.size model.meetingParticipants <= 100 then
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

                                else if Set.size model.meetingParticipants <= 100 then
                                    Set.insert key model.meetingParticipants

                                else
                                    model.meetingParticipants
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
                    let
                        newMeeting =
                            { title = Validate.fromValid valid, duration = model.meetingDuration, participants = model.meetingParticipants }
                    in
                    ( { model
                        | meetings =
                            Dict.insert id
                                newMeeting
                                model.meetings
                      }
                    , Effect.fromCmd <| requestCreateMeeting model.endpoint user.jwt id newMeeting
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

        DeleteMeeting id ->
            ( { model | meetings = Dict.remove id model.meetings }
            , Effect.fromCmd <| requestDeleteMeeting model.endpoint user.jwt id
            )

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

        TogglePurchaseModal ->
            ( { model | purchaseModalActive = not model.purchaseModalActive }, Effect.none )

        SetPurchaseTab tab ->
            let
                effect =
                    case tab of
                        Checkout ->
                            if model.checkoutIntent == Nothing then
                                Effect.fromCmd <| requestBeginCheckout model.endpoint user.jwt model.checkoutCredits

                            else
                                Effect.none

                        _ ->
                            Effect.none
            in
            ( { model | purchaseModalTab = tab }, effect )

        CheckoutIntentResponse resp ->
            case resp of
                RemoteData.Success data ->
                    let
                        amount =
                            data.amount

                        secret =
                            data.clientSecret

                        id =
                            data.orderId
                    in
                    ( { model | checkoutIntent = Just secret }, Effect.none )

                _ ->
                    ( model, Effect.none )

        SetPurchaseCreditsAmount value ->
            ( { model | checkoutCredits = String.toInt value |> Maybe.withDefault 5 }, Effect.none )

        ViewScheduleResults results ->
            ( { model | viewSchedule = Just results }, Effect.none )

        CloseScheduleModal ->
            ( { model | viewSchedule = Nothing }, Effect.none )

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
    ul [ class "menu-list participant-list" ]
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
    form [ class "form", onSubmit SubmitNewParticipant ]
        [ label [ class "label", for "participant-name-input" ] [ text "Add Participant" ]
        , div [ class "field has-addons" ]
            [ div [ class "control", style "width" "100%" ]
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
            div [ class "columns p-2" ]
                [ div [ class "column is-full" ]
                    [ div [ id "available-calendar" ]
                        [ Calendar.view model.availableCalendar |> Html.map (CalendarMsg AvailableCalendar) ]
                    ]
                ]

        ParticipantCalendarSlider ->
            div
                [ class "columns"
                , classList [ ( "is-clipped", model.deleteParticipant /= Nothing ) ]
                ]
                [ case model.deleteParticipant of
                    Just { key, affectedMeetings, removedMeetings } ->
                        let
                            totalAffected =
                                Dict.size removedMeetings + Dict.size affectedMeetings

                            ableToDelete =
                                totalAffected < 25
                        in
                        div [ class "modal is-active" ]
                            [ div [ class "modal-background" ] []
                            , if not ableToDelete then
                                div [ class "modal-content" ]
                                    [ section [ class "message is-danger" ]
                                        [ div
                                            [ class "message-header" ]
                                            [ p [] [ text "Unable to delete this participant" ]
                                            , button [ class "delete", onClick CloseDeleteModal ] []
                                            ]
                                        , div [ class "message-body" ]
                                            [ p []
                                                [ text
                                                    """
                                            This participant is a member of too many meetings. Please delete this participant's
                                            meetings manually until there are 24 meetings or less.
                                            """
                                                ]
                                            , p []
                                                [ text <| "Currently, there are " ++ String.fromInt totalAffected ++ " meetings with this participant" ]
                                            ]
                                        ]
                                    ]

                              else
                                div [ class "modal-card" ]
                                    [ header [ class "modal-card-head" ]
                                        [ h3 [ class "modal-card-title" ] [ text "Are you sure you want to delete ", code [] [ text key ], text "?" ]
                                        , button [ class "delete", onClick CloseDeleteModal ] []
                                        ]
                                    , if Dict.isEmpty removedMeetings && Dict.isEmpty affectedMeetings then
                                        section [ class "modal-card-body" ]
                                            [ div
                                                [ class "content" ]
                                                [ p [] [ text "This participant has not been added to any meetings." ]
                                                ]
                                            ]

                                      else
                                        section [ class "modal-card-body" ]
                                            [ div [ class "columns" ]
                                                [ if Dict.isEmpty removedMeetings then
                                                    text ""

                                                  else
                                                    div [ class "content column" ]
                                                        [ h4 [ class "subtitle is-6" ] [ text "These meetings will be deleted:" ]
                                                        , ul [] <| List.map (\meeting -> li [] [ code [] [ text meeting.title ] ]) (Dict.values removedMeetings)
                                                        ]
                                                , if Dict.isEmpty affectedMeetings then
                                                    text ""

                                                  else
                                                    div [ class "content column" ]
                                                        [ h4 [ class "subtitle is-6" ] [ code [] [ text key ], text " will be removed from these meetings" ]
                                                        , ul [] <| List.map (\meeting -> li [] [ code [] [ text meeting.title ] ]) (Dict.values affectedMeetings)
                                                        ]
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
                , div [ class "column is-one-fifth" ]
                    [ div [ class "columns is-multiline" ]
                        [ div [ class "column is-full" ] [ createParticipantForm model ]
                        , div [ class "column is-full" ]
                            [ aside [ class "menu" ]
                                [ p [ class "menu-label" ] [ text "Participants" ]
                                , participantList model
                                ]
                            ]
                        ]
                    ]
                , div [ class "column" ]
                    [ div
                        [ id "participant-calendar"
                        , classList [ ( "loading ignore-pointer-events", model.selectedParticipant == Nothing ) ]
                        ]
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
            div [ class "meeting-configuration container columns" ] <|
                [ aside [ class "column is-one-quarter" ]
                    [ div [ class "columns is-multiline" ]
                        [ form [ class "column is-full", onSubmit CreateMeeting ]
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
                                    [ div [ class "select is-fullwidth is-rounded is-medium" ]
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
                            , div [ class "panel is-info meeting-panel" ]
                                [ h2
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
                                , div [ class "panel-block" ]
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
                                , div [ class "meeting-participant-list" ]
                                    (Dict.keys model.participants
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
                                                            , disabled <| Set.size model.meetingParticipants >= 100
                                                            , checked <| Set.member name model.meetingParticipants
                                                            , onCheck <| SelectMeetingParticipant name
                                                            ]
                                                            []
                                                        , text name
                                                        ]
                                            )
                                    )
                                ]
                            , div [ class "field" ]
                                [ div [ class "control", style "width" "100%" ]
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
                                                                            ++ List.map dayToEvent participant.blockedDays
                                                                    )
                                                                |> Maybe.withDefault []
                                                        )
                                                    |> List.concat
                                                    |> mergeTimes
                                                    |> subtractTimes (model.availableCalendar.events ++ List.map dayToEvent model.availableCalendar.blockedDays)
                                                    |> List.filter (\event -> (event.end - event.start) + 1 >= meeting.duration)

                                            meetingExpanded =
                                                Set.member id model.expandedMeetings
                                        in
                                        div
                                            [ class "column meeting-item is-4 panel is-primary"
                                            , classList [ ( "is-danger", List.isEmpty meetingTimes ) ]
                                            ]
                                        <|
                                            [ div [ class "panel-heading is-flex is-justify-content-space-between" ]
                                                [ span []
                                                    [ text <|
                                                        meeting.title
                                                            ++ " ("
                                                            ++ (durationToString meeting.duration)
                                                            ++ ")"
                                                    ]
                                                , button [ class "delete", onClick <| DeleteMeeting id ] []
                                                ]
                                            , div
                                                [ class "panel-block" ]
                                                [ div
                                                    [ class "tags are-medium" ]
                                                  <|
                                                    List.map (\name -> span [ class "tag is-dark" ] [ text name ]) <|
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

        ScheduleMeetingsSlider ->
            div
                [ class "columns p-2"
                , classList [ ( "is-clipped", model.purchaseModalActive ) ]
                ]
                [ div
                    [ class "modal"
                    , classList [ ( "is-active", model.purchaseModalActive ) ]
                    ]
                    [ div [ class "modal-background", onClick TogglePurchaseModal ] []
                    , div [ class "modal-content" ]
                        [ div [ class "box" ]
                            [ div [ class "tabs is-centered" ]
                                [ ul []
                                    [ li [ classList [ ( "is-active", model.purchaseModalTab == SelectCredits ) ] ] [ a [ class "ignore-pointer-events" ] [ text "Select Credits" ] ]
                                    , li [ classList [ ( "is-active", model.purchaseModalTab == Checkout ) ] ] [ a [ class "ignore-pointer-events" ] [ text "Checkout with Stripe" ] ]
                                    ]
                                ]
                            , if model.purchaseModalTab == SelectCredits then
                                form [ onSubmit <| SetPurchaseTab Checkout ]
                                    [ div [ class "field" ]
                                        [ label [ class "label" ] [ text "Choose how many credits to purchase" ]
                                        , div [ class "control has-icons-left" ]
                                            [ div [ class "select is-fullwidth is-rounded is-medium" ]
                                                [ select [ onInput SetPurchaseCreditsAmount ]
                                                    (let
                                                        purchaseOptions =
                                                            [ 5, 10, 25, 50 ]

                                                        values =
                                                            List.map String.fromInt purchaseOptions
                                                     in
                                                     purchaseOptions
                                                        |> List.map
                                                            (\credits ->
                                                                option [ value (String.fromInt credits), selected <| model.checkoutCredits == credits ] [ text <| String.fromInt credits ++ " - " ++ displayCreditCost credits ]
                                                            )
                                                    )
                                                ]
                                            , div [ class "icon is-small is-left" ]
                                                [ Icon.view Solid.coins ]
                                            ]
                                        ]
                                    , p [ class "subtitle" ] [ text "Note: purchasing more credits is cheaper per-credit." ]
                                    , button [ class "button is-success" ] [ text "Continue to Checkout" ]
                                    ]

                              else
                                div []
                                    [ p [ class "subtitle" ] [ text "Pay securely with Stripe" ]
                                    , p [ class "subtitle is-6 mt-1" ] [ text <| "Total: " ++ displayCreditCost model.checkoutCredits ]
                                    , Maybe.map
                                        (\secret ->
                                            let
                                                cost =
                                                    computeCreditCostCents model.checkoutCredits
                                            in
                                            Html.node "stripe-web-component"
                                                [ attribute "amount" (String.fromInt cost), attribute "client-secret" secret ]
                                                []
                                        )
                                        model.checkoutIntent
                                        |> Maybe.withDefault (Icon.view Solid.spinner)
                                    , p [ class "subtitle is-6 mt-1" ] [ text "Note: you will be redirected to a confirmation page upon successful payment" ]
                                    ]
                            ]
                        ]
                    ]
                , div [ class "column is-3" ]
                    [ div [ class "card" ]
                        [ div [ class "card-content" ]
                            [ div [ class "media" ]
                                [ div [ class "media-left" ] [ Icon.view Solid.user ]
                                , div [ class "media-content" ]
                                    [ h2 [ class "title is-4" ] [ text <| "Credits: " ++ String.fromInt model.credits ]
                                    , p [ class "subtitle is-6" ] [ text "Each credit can be used to compute a schedule" ]
                                    ]
                                ]
                            ]
                        , Html.footer [ class "card-footer" ]
                            [ button [ class "card-footer-item button is-success", onClick TogglePurchaseModal ] [ text "Purchase more credits" ]
                            ]
                        ]
                    ]
                , div [ class "column is-9" ]
                    [ div
                        [ class "modal"
                        , classList [ ( "is-active", model.viewSchedule /= Nothing ) ]
                        ]
                        [ div [ class "modal-background", onClick CloseScheduleModal ] []
                        , div [ class "modal-content" ]
                            [ div [ class "box" ]
                                (model.viewSchedule
                                    |> Maybe.map
                                        (\result ->
                                            let
                                                dayDict =
                                                    result
                                                        |> List.filterMap
                                                            (\row ->
                                                                String.toInt row.id
                                                                    |> Maybe.andThen (\id -> Dict.get id model.meetings)
                                                                    |> Maybe.map (\val -> { meeting = val, time = row.time  } )
                                                            )
                                                        |> groupBy (\row -> timeToDayString row.time.start )
                                            in
                                            [text <| Debug.toString dayDict]
                                        )
                                    |> Maybe.withDefault
                                        []
                                )
                            ]
                        ]
                    , table [ class "table is-fullwidth is-striped" ]
                        [ thead []
                            [ tr []
                                [ th [] [ text "Created" ]
                                , th [] [ text "Failed Meetings" ]
                                , th [] [ text "Errors" ]
                                , th [] [ text "Status" ]
                                , th [] []
                                ]
                            ]
                        , tbody []
                            (model.schedules
                                |> List.map
                                    (\schedule ->
                                        tr []
                                            [ td []
                                                [ text <|
                                                    case schedule.created of
                                                        Long val ->
                                                            String.toInt val
                                                                |> Maybe.map Time.millisToPosix
                                                                |> Maybe.map2 (\zone -> \time -> formatTime zone time) model.zone
                                                                |> Maybe.withDefault ""
                                                ]
                                            , td []
                                                [ text
                                                    (Maybe.withDefault [] schedule.failed
                                                        |> List.filterMap
                                                            (\id ->
                                                                String.toInt id
                                                                    |> Maybe.andThen (\key -> Dict.get key model.meetings)
                                                                    |> Maybe.map (\meeting -> meeting.title ++ " (" ++ (durationToString meeting.duration) ++ ")")
                                                            )
                                                        |> String.join ","
                                                    )
                                                ]
                                            , td [] <|
                                                let
                                                    content =
                                                        Maybe.withDefault "" schedule.error

                                                    hasExtra =
                                                        String.length content > 20
                                                in
                                                (text <| String.left 20 content)
                                                    :: (if hasExtra then
                                                            [ span
                                                                [ tooltip content
                                                                , class "has-tooltip-bottom has-tooltip-multiline"
                                                                ]
                                                                [ text "..." ]
                                                            ]

                                                        else
                                                            []
                                                       )
                                            , td [] <|
                                                case schedule.results of
                                                    Just resultList ->
                                                        let
                                                            allMeetingsExist =
                                                                resultList
                                                                    |> List.all
                                                                        (\result ->
                                                                            String.toInt result.id
                                                                                |> Maybe.map (\id -> Dict.member id model.meetings)
                                                                                |> Maybe.withDefault True
                                                                        )
                                                        in
                                                        [ p []
                                                            [ text "Valid: "
                                                            , span []
                                                                [ Icon.view <|
                                                                    if allMeetingsExist then
                                                                        Solid.check

                                                                    else
                                                                        Solid.xmark
                                                                ]
                                                            ]
                                                        ]

                                                    Nothing ->
                                                        []
                                            , td []
                                                [ case schedule.results of
                                                    Just result ->
                                                        button
                                                            [ class "button is-link is-small is-icon is-rounded"
                                                            , onClick <| ViewScheduleResults result
                                                            ]
                                                            [ Icon.view Solid.search ]

                                                    Nothing ->
                                                        text ""
                                                ]
                                            ]
                                    )
                            )
                        , tfoot [] []
                        ]
                    ]
                ]


computeCreditCostCents : Int -> Int
computeCreditCostCents credits =
    25 * (round <| 9 * (toFloat credits ^ 0.725))


displayCreditCost : Int -> String
displayCreditCost credits =
    let
        cost =
            computeCreditCostCents credits
    in
    "$" ++ (String.fromInt <| cost // 100) ++ "." ++ String.padRight 2 '0' (String.fromInt <| modBy 100 cost)


view : Shared.Model -> Model -> View Msg
view shared model =
    View "Zeitplan - Schedule"
        [ zeitplanNav
            { logo = shared.logo
            , shared = shared
            }
            |> Html.map SharedMsg
        , div
            [ class "pageloader"
            , classList [ ( "is-active", model.initialLoad == RemoteData.NotAsked || model.initialLoad == RemoteData.Loading ) ]
            ]
            [ span [ class "title" ] [ text "Please wait while we fetch your information" ]
            ]
        , div [ class "container is-fullhd" ]
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
                            , div [ class "steps-content" ] [ text "Available Times" ]
                            ]
                        ]
                    , li
                        [ tooltip "Add people to meet with - and block off times they can't meet"
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
                            [ span [ class "steps-marker icon is-small" ] [ Icon.view Solid.users ]
                            , div [ class "steps-content" ]
                                [ text "Participants"
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
                                [ text "Meetings"
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
                    , li
                        [ tooltip "Find a way to schedule your meetings"
                        , class "steps-segment has-tooltip-bottom has-tooltip-multiline"
                        , classList
                            [ ( "is-active", model.slider == ScheduleMeetingsSlider )
                            , ( "ignore-pointer-events", Dict.isEmpty model.meetings )
                            ]
                        ]
                        [ a
                            [ href "#"
                            , class "has-text-dark"
                            , onClick <| SetSliderState ScheduleMeetingsSlider
                            ]
                            [ span [ class "steps-marker icon is-small" ] [ Icon.view Solid.robot ]
                            , div [ class "steps-content" ] [ text "Compute Schedule" ]
                            ]
                        ]
                    ]
                , sliderView model
                ]
            ]
        , View.footer
        ]
