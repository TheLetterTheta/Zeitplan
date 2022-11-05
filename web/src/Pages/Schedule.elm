module Pages.Schedule exposing (Model, Msg, Participant, page)

import Array
import Calendar as Calendar exposing (Event, encodeEvent)
import Dict exposing (Dict)
import Effect exposing (Effect, fromCmd)
import Gen.Params.Schedule exposing (Params)
import Html exposing (Attribute, Html, button, div, p, span, table, tbody, td, text, th, thead, tr, wbr)
import Html.Attributes exposing (class, classList, style, type_)
import Html.Events exposing (onClick, onMouseDown, onMouseEnter, onMouseLeave, onMouseUp, stopPropagationOn)
import Json.Decode as Decode
import Json.Encode as Encode
import Page
import Request
import Shared exposing (saveKey)
import View exposing (View)


page : Shared.Model -> Request.With Params -> Page.With Model Msg
page shared req =
    Page.advanced
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }



-- INIT


type alias Participant =
    { events : List Event
    , name : String
    }


encodeParticipant : Participant -> Encode.Value
encodeParticipant p =
    Encode.object
        [ ( "events", Encode.list encodeEvent p.events )
        , ( "name", Encode.string p.name )
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
    }


init : ( Model, Effect Msg )
init =
    let
        ( participantCalendar, participantEffects ) =
            Calendar.init
    in
    ( { participants = Dict.empty
      , participantCalendar = participantCalendar
      }
    , Effect.batch
        [ Effect.map (\a -> CalendarMsg ParticipantCalendar a) participantEffects
        , { key = "event"
          , value =
                encodeMeeting <|
                    Meeting
                        (Dict.singleton "t" (Participant [ Event 0 1 False False, Event 1 3 True False ] "Participant"))
                        30
                        "Meeting"
          }
            |> saveKey
            |> fromCmd
        ]
    )



-- UPDATE


type Msg
    = NoOp
    | CalendarMsg Calendar Calendar.Msg


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )

        CalendarMsg calendar calendarMsg ->
            case calendar of
                ParticipantCalendar ->
                    let
                        ( newCalendar, effects ) =
                            Calendar.update calendarMsg model.participantCalendar
                    in
                    ( { model | participantCalendar = newCalendar }, Effect.map (\a -> CalendarMsg ParticipantCalendar a) effects )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none



-- VIEW


type Calendar
    = ParticipantCalendar


view : Model -> View Msg
view model =
    View "Schedule"
        [ div [ class "schedule", style "width" "90%" ]
            [ Calendar.view model.participantCalendar |> Html.map (CalendarMsg ParticipantCalendar)
            ]
        ]
