module Pages.Schedule exposing (Model, Msg, Participant, page)

import Browser.Dom exposing (setViewportOf)
import Calendar exposing (Event, Weekday, encodeEvent)
import Decoders exposing (AuthUser)
import Dict exposing (Dict)
import Effect exposing (Effect, fromCmd)
import Gen.Params.Schedule exposing (Params)
import Html exposing (Html, aside, button, div, form, input, li, p, text, ul)
import Html.Attributes exposing (class, classList, id, placeholder, type_, value)
import Html.Events exposing (onClick, onInput, onSubmit)
import Json.Encode as Encode
import Page
import Request
import Shared exposing (saveKey)
import Task
import Time exposing (Posix)
import View exposing (View, footer, zeitplanNav)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared _ =
    Page.protected.advanced
        (\_ ->
            { init = init
            , update = update
            , view = view shared
            , subscriptions = subscriptions
            }
        )



-- INIT


type alias Participant =
    { events : List Event
    , name : String
    , blockedDays : List Weekday
    }


encodeParticipant : Participant -> Encode.Value
encodeParticipant participant =
    Encode.object
        [ ( "events", Encode.list encodeEvent participant.events )
        , ( "name", Encode.string participant.name )
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


type alias Model =
    { participants : Dict String Participant
    , participantCalendar : Calendar.Model
    , selectedParticipant : Maybe String
    , newParticipantName : String
    }


init : ( Model, Effect Msg )
init =
    let
        ( participantCalendar, participantEffects ) =
            Calendar.init
    in
    ( { participants = Dict.empty
      , participantCalendar = participantCalendar
      , selectedParticipant = Nothing
      , newParticipantName = ""
      }
    , Effect.batch
        [ Effect.map (\a -> CalendarMsg ParticipantCalendar a) participantEffects
        , { key = "event"
          , value =
                encodeMeeting <|
                    Meeting
                        (Dict.singleton "t" (Participant [ Event 0 1 False [], Event 1 3 False [] ] "Participant" []))
                        30
                        "Meeting"
          }
            |> saveKey
            |> fromCmd
        , fromCmd <| Task.attempt (\_ -> NoOp) <| setViewportOf "participant-calendar" 0 310
        ]
    )



-- UPDATE


type Msg
    = SelectParticipant String
    | ChangeParticipantName String
    | AddNewParticipant Posix
    | SubmitNewParticipant
    | CalendarMsg Calendar Calendar.Msg
    | SharedMsg Shared.Msg
    | NoOp


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
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
                    }
            in
            ( { model
                | selectedParticipant = Just participantKey
                , participantCalendar = updatedCalendar
              }
            , Effect.none
            )

        ChangeParticipantName name ->
            ( { model | newParticipantName = name }, Effect.none )

        SubmitNewParticipant ->
            ( model, Effect.fromCmd <| Task.perform AddNewParticipant Time.now )

        AddNewParticipant time ->
            let
                timeString : String
                timeString =
                    String.fromInt <| Time.posixToMillis time

                newParticipant : Participant
                newParticipant =
                    Participant [] model.newParticipantName []
            in
            ( { model
                | newParticipantName = ""
                , participants = Dict.insert timeString newParticipant model.participants
              }
            , Effect.none
            )

        CalendarMsg calendar calendarMsg ->
            case calendar of
                ParticipantCalendar ->
                    let
                        ( newCalendar, effects ) =
                            Calendar.update calendarMsg model.participantCalendar

                        participants : Dict String Participant
                        participants =
                            case model.selectedParticipant of
                                Just key ->
                                    Dict.update key
                                        (Maybe.map
                                            (\participant ->
                                                { participant | events = newCalendar.events }
                                            )
                                        )
                                        model.participants

                                Nothing ->
                                    model.participants
                    in
                    ( { model | participants = participants, participantCalendar = newCalendar }, Effect.map (\a -> CalendarMsg ParticipantCalendar a) effects )

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


participantList : Model -> Html Msg
participantList model =
    ul [ class "participant-list" ]
        (model.participants
            |> Dict.toList
            |> List.map
                (\( key, participant ) ->
                    li
                        [ class "participant"
                        , classList [ ( "active", model.selectedParticipant == Just key ) ]
                        , onClick <| SelectParticipant key
                        ]
                        [ p
                            [ class "participant-name" ]
                            [ text participant.name ]
                        ]
                )
        )


createParticipantForm : Model -> Html Msg
createParticipantForm model =
    form [ class "form", onSubmit SubmitNewParticipant ]
        [ input [ class "input", type_ "text", value model.newParticipantName, placeholder "Name", onInput ChangeParticipantName ] []
        , button [ class "button", type_ "submit" ]
            []
        ]


view : Shared.Model -> Model -> View Msg
view shared model =
    View "Schedule"
        [ zeitplanNav
            { logo = shared.logo
            , shared = shared
            }
            |> Html.map SharedMsg
        , div [ class "container is-fullhd" ]
            [ div [ class "box participants" ]
                [ aside []
                    [ participantList model
                    , createParticipantForm model
                    ]
                , div [ id "participant-calendar" ]
                    [ Calendar.view model.participantCalendar |> Html.map (CalendarMsg ParticipantCalendar) ]
                ]
            ]
        , footer
        ]
