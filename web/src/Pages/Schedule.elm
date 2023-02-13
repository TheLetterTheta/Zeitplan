module Pages.Schedule exposing (Model, Msg, Participant, page)

import Browser.Dom exposing (setViewportOf)
import Calendar exposing (Event, Weekday, dayString, encodeEvent, isSaveMsg, stringToDay)
import Decoders exposing (AuthUser)
import Dict exposing (Dict)
import Effect exposing (Effect, fromCmd)
import FontAwesome as Icon
import FontAwesome.Attributes exposing (fa10x, spin)
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
import Html exposing (Html, a, aside, button, div, form, input, li, p, span, text, ul)
import Html.Attributes exposing (class, classList, href, id, placeholder, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
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
import View exposing (View, footer, zeitplanNav)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared _ =
    Page.protected.advanced
        (\user ->
            { init = init shared user
            , update = update
            , view = view shared
            , subscriptions = subscriptions
            }
        )



-- INIT


type alias Participant =
    { events : List Event
    , blockedDays : List Weekday
    }


encodeParticipant : Participant -> Encode.Value
encodeParticipant participant =
    Encode.object
        [ ( "events", Encode.list encodeEvent participant.events )
        ]


type alias Meeting =
    { participants : Dict String Participant
    , timespan : Int
    , title : String
    }


encodeMeeting : Meeting -> Encode.Value
encodeMeeting m =
    Encode.object
        [ ( "participants", Encode.dict identity encodeParticipant m.participants )
        , ( "timespan", Encode.int m.timespan )
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



-- VALIDATOR


participantNameValidator : Dict String a -> Validator String String
participantNameValidator dict =
    Validate.all
        [ ifBlank identity "Must enter a participant name"
        , ifTrue (\name -> Dict.member name dict) "Participant already exists!"
        ]



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
    , jwt : String
    , endpoint : String
    , saveAvailableCalendarQueued : Bool
    , participantSaveQueue : Set String
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
      , jwt = user.jwt
      , endpoint = shared.graphQlEndpoint
      , saveAvailableCalendarQueued = False
      , participantSaveQueue = Set.empty
      }
    , Effect.batch
        [ Effect.map (\a -> CalendarMsg ParticipantCalendar a) participantEffects
        , Effect.map (\a -> CalendarMsg ParticipantCalendar a) availableEffects
        , { key = "event"
          , value =
                encodeMeeting <|
                    Meeting
                        (Dict.singleton "t" (Participant [ Event 0 1 False [], Event 1 3 False [] ] []))
                        30
                        "Meeting"
          }
            |> saveKey
            |> fromCmd
        , fromCmd <| Task.attempt (\_ -> NoOp) <| setViewportOf "participant-calendar" 0 310
        , fromCmd <| requestInitialLoad shared.graphQlEndpoint user.jwt
        ]
    )



-- UPDATE


type Msg
    = SelectParticipant String
    | ChangeParticipantName String
    | SubmitNewParticipant
    | SaveParticipantSuccess (RemoteData (Graphql.Http.Error SaveParticipantResponse) SaveParticipantResponse)
    | CalendarMsg Calendar Calendar.Msg
    | SaveAvailableCalendar
    | SharedMsg Shared.Msg
    | SaveAvailableCalendarSuccess (RemoteData (Graphql.Http.Error (List SaveAvailableResponse)) (List SaveAvailableResponse))
    | SetSliderState SliderState
    | InitialDataLoaded (RemoteData (Graphql.Http.Error InitialQuery) InitialQuery)
    | SaveParticipantQueue
    | NoOp


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
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
                                    { calendar
                                        | events =
                                            Dict.get key participants
                                                |> Maybe.map .events
                                                |> Maybe.withDefault []
                                        , blockedDays =
                                            Dict.get key participants
                                                |> Maybe.map .blockedDays
                                                |> Maybe.withDefault []
                                    }

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

                updatedCalendar : Calendar.Model
                updatedCalendar =
                    { calendar
                        | events =
                            Dict.get participantKey model.participants
                                |> Maybe.map .events
                                |> Maybe.withDefault calendar.events
                        , blockedDays =
                            Dict.get participantKey model.participants
                                |> Maybe.map .blockedDays
                                |> Maybe.withDefault calendar.blockedDays
                    }
            in
            ( { model
                | selectedParticipant = Just participantKey
                , participantCalendar = updatedCalendar
              }
            , Effect.none
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
                                                requestSaveParticipant model.endpoint model.jwt key participant
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
                        requestSaveParticipant model.endpoint model.jwt name newParticipant
                    )

                _ ->
                    ( model, Effect.none )

        SaveParticipantSuccess _ ->
            ( model, Effect.none )

        SaveAvailableCalendar ->
            ( { model | saveAvailableCalendarQueued = False }
            , Effect.fromCmd <|
                requestSaveAvailableEvents model.endpoint model.jwt model.availableCalendar.events
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
            ( { model | slider = s }, Effect.none )

        SharedMsg sharedMsg ->
            ( model, Effect.fromShared sharedMsg )

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
                            [ text key ]
                        ]
                )
        )


createParticipantForm : Model -> Html Msg
createParticipantForm model =
    form [ class "form participant-form", onSubmit SubmitNewParticipant ]
        [ div [ class "field has-addons" ]
            [ div [ class "control" ]
                [ input
                    [ class "input"
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
            div [ class "participants" ]
                [ div [ class "participant-list-container" ]
                    [ aside [ class "participant-list menu" ]
                        [ p [ class "menu-label" ] [ text "Participants" ]
                        , participantList model
                        ]
                    , createParticipantForm model
                    ]
                , div [ id "participant-calendar" ]
                    [ div
                        [ classList [ ( "loading", model.selectedParticipant == Nothing ) ] ]
                        [ Calendar.view model.participantCalendar |> Html.map (CalendarMsg ParticipantCalendar) ]
                    ]
                ]

        MeetingConfigurationSlider ->
            div [ class "box meeting-configuration" ]
                []


view : Shared.Model -> Model -> View Msg
view shared model =
    View "Schedule"
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
                            [ class "steps-segment"
                            , classList [ ( "is-active", model.slider == AvailableCalendarSlider ) ]
                            ]
                            [ a [ href "#", class "has-text-dark", onClick <| SetSliderState AvailableCalendarSlider ]
                                [ span [ class "steps-marker icon is-small" ] [ Icon.view Solid.calendarWeek ]
                                , div [ class "steps-content" ] [ text "Set Available Times" ]
                                ]
                            ]
                        , li
                            [ class "steps-segment"
                            , classList [ ( "is-active", model.slider == ParticipantCalendarSlider ) ]
                            ]
                            [ a [ href "#", class "has-text-dark", onClick <| SetSliderState ParticipantCalendarSlider ]
                                [ span [ class "steps-marker icon is-small" ] [ Icon.view Solid.user ]
                                , div [ class "steps-content" ] [ text "Add Participants" ]
                                ]
                            ]
                        , li
                            [ class "steps-segment"
                            , classList [ ( "is-active", model.slider == MeetingConfigurationSlider ) ]
                            ]
                            [ a [ href "#", class "has-text-dark", onClick <| SetSliderState MeetingConfigurationSlider ]
                                [ span [ class "steps-marker icon is-small" ] [ Icon.view Solid.calendarPlus ]
                                , div [ class "steps-content" ] [ text "Create Meetings" ]
                                ]
                            ]
                        ]
                    , sliderView model
                    ]
                ]
        , footer
        ]
