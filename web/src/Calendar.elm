module Calendar exposing (Event, Model, Msg, encodeEvent, init, update, view)

import Array
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
import View exposing (View)



-- VARS


const_interval : Int
const_interval =
    30


slots : Int
slots =
    minutesInDay // const_interval


type Weekday
    = Sunday
    | Monday
    | Tuesday
    | Wednesday
    | Thursday
    | Friday
    | Saturday


dayString : Weekday -> String
dayString d =
    case d of
        Sunday ->
            "Sunday"

        Monday ->
            "Monday"

        Tuesday ->
            "Tuesday"

        Wednesday ->
            "Wednesday"

        Thursday ->
            "Thursday"

        Friday ->
            "Friday"

        Saturday ->
            "Saturday"


days : Array.Array Weekday
days =
    Array.fromList [ Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday ]


minutesInDay : Int
minutesInDay =
    60 * 24



-- TYPES


type Direction
    = Down
    | Up


type alias Event =
    { start : Int
    , end : Int
    , draft : Bool
    , dragging : Bool
    }


encodeEvent : Event -> Encode.Value
encodeEvent e =
    Encode.object
        [ ( "start", Encode.int e.start )
        , ( "end", Encode.int e.end )
        ]


type alias EditEvent =
    { event : Event, shadowEvent : Maybe Event, time : Int }


type alias MoveEventEnd =
    { event : Event, end : Ends }



-- MODEL


type CalendarState
    = Resizing MoveEventEnd
    | Dragging EditEvent
    | Creating EditEvent
    | Idle


type alias Model =
    { events : List Event
    , state : CalendarState
    }



-- INIT


init : ( Model, Effect Msg )
init =
    ( { events = []
      , state = Idle
      }
    , Effect.none
    )



-- FUNCTIONS


timeSlotToString : Int -> String
timeSlotToString t =
    let
        timeInDay =
            const_interval * modBy slots (t - 1)

        time =
            modBy 60 timeInDay

        hour =
            timeInDay // 60

        ( meridian, twelveHour ) =
            if hour > 12 then
                ( "PM", hour - 12 )

            else if hour == 0 then
                ( "AM", 12 )

            else
                ( "AM", hour )
    in
    String.fromInt twelveHour ++ ":" ++ (String.padLeft 2 '0' <| String.fromInt time) ++ " " ++ meridian


addEvent : Event -> List Event -> ( Event, List Event )
addEvent e l =
    let
        ( remainderEvents, conflictingEvents ) =
            List.partition (\ev -> ev.end < (e.start - 1) || ev.start > (1 + e.end)) l

        addedEvent =
            conflictingEvents
                |> List.foldl
                    (\ev ->
                        \n ->
                            { ev
                                | start = min ev.start n.start
                                , end = max ev.end n.end
                            }
                    )
                    e
    in
    ( addedEvent, addedEvent :: remainderEvents )



-- UPDATE


type Ends
    = Start
    | End


type Msg
    = BeginCreateEvent Int
    | EndCreateEvent
    | MouseEnterTime Int
    | MouseLeaveCalendar
    | BeginDragEvent Event Int
    | DragEventTo Int
    | DeleteEvent Event
    | EndDragEvent
    | ResizeEvent Ends Event
    | ResizeEventTo Int
    | EndResizeEvent
    | NoOp


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )

        BeginCreateEvent t ->
            let
                event =
                    Event t t True False
            in
            ( { model | state = Creating { event = event, shadowEvent = Just event, time = t } }, Effect.none )

        EndCreateEvent ->
            case model.state of
                Creating { event } ->
                    let
                        ( _, newList ) =
                            addEvent { event | draft = False } model.events
                    in
                    ( { model | events = newList, state = Idle }, Effect.none )

                _ ->
                    ( model, Effect.none )

        MouseEnterTime t ->
            case model.state of
                Creating { event, time } ->
                    let
                        ( newStart, newEnd ) =
                            if t < time then
                                ( t, time )

                            else
                                ( time, t )

                        newEvent =
                            { event | end = newEnd, start = newStart }
                    in
                    ( { model | state = Creating { event = newEvent, shadowEvent = Just newEvent, time = time } }, Effect.none )

                _ ->
                    ( model, Effect.none )

        MouseLeaveCalendar ->
            ( { model | state = Idle }, Effect.none )

        BeginDragEvent event t ->
            let
                events =
                    model.events
                        |> List.map
                            (\ev ->
                                if ev == event then
                                    { ev | dragging = True }

                                else
                                    ev
                            )
            in
            ( { model | events = events, state = Dragging { event = event, shadowEvent = Nothing, time = t } }, Effect.none )

        DragEventTo t ->
            case model.state of
                Dragging { event, time } ->
                    let
                        dragDistance =
                            t - time

                        newEvent =
                            { event
                                | start = event.start + dragDistance
                                , end = event.end + dragDistance
                            }
                    in
                    ( { model
                        | state = 
                            Dragging { event = newEvent
                            , shadowEvent = Just { newEvent | draft = True, dragging = True }
                            , time = t } 
                        }
                    , Effect.none )

                _ ->
                    ( model, Effect.none )

        EndDragEvent ->
            case model.state of
                Dragging { event, time } ->
                    let
                        clearDragging =
                            \e -> { e | dragging = False, draft = False }

                        ( _, newEvents ) =
                            addEvent { event | dragging = False } <|
                                List.filter (\current -> not current.dragging) model.events
                    in
                    ( { model | events = newEvents, state = Idle }, Effect.none )

                _ ->
                    ( model, Effect.none )

        DeleteEvent event ->
            let
                filterEvent =
                    List.filter (\pEvent -> pEvent /= event)
            in
            ( { model | events = filterEvent model.events }, Effect.none )

        ResizeEvent end event ->
            ( { model | state = Resizing { event = event, end = end } }, Effect.none )

        {--
        TODO: PLEASE - UPDATE this to not have overlapping events
        --}
        ResizeEventTo time ->
            case model.state of
                Resizing { event, end } ->
                    let
                        newEvent =
                            case end of
                                Start ->
                                    { event | start = min event.end time }

                                End ->
                                    { event | end = max event.start time }
                    in
                    ( { model
                        | state = Resizing { event = newEvent, end = end }
                        , events =
                            model.events
                                |> List.map
                                    (\e ->
                                        if e == event then
                                            newEvent

                                        else
                                            e
                                    )
                      }
                    , Effect.none
                    )

                _ ->
                    ( model, Effect.none )

        EndResizeEvent ->
            ( { model | state = Idle }, Effect.none )



-- VIEW


view : Model -> Html Msg
view model =
    let
        editEvent =
            case model.state of
                Creating { shadowEvent } ->
                    shadowEvent

                Dragging { shadowEvent } ->
                    shadowEvent

                _ ->
                    Nothing

        events =
            model.events

        ignoreEvent : String -> Attribute Msg
        ignoreEvent s =
            stopPropagationOn s <| Decode.succeed ( NoOp, True )

        viewDay day =
            th []
                [ span [ class "day-name" ]
                    [ text <| dayString day ]
                ]

        viewAllDay day =
            td
                [ class "all-day-interval"
                ]
                []

        viewTime i j =
            let
                index =
                    slots * j + i

                matchingEvent =
                    events
                        |> List.filter (\e -> index >= e.start && index <= e.end)
                        |> List.head

                matchingDraft =
                    editEvent
                        |> Maybe.andThen
                            (\event ->
                                if index >= event.start && index <= event.end then
                                    Just event

                                else
                                    Nothing
                            )

                viewDraft e =
                    div
                        [ class "event"
                        , classList
                            [ ( "event-start", e.start == index )
                            , ( "event-end", e.end == index )
                            , ( "dragging", e.dragging)
                            , ( "draft", e.draft)
                            ]
                        ]
                    <|
                        if e.start == index then
                            [ p [ class "event-time" ] [ text <| timeSlotToString e.start ++ " - " ++ timeSlotToString (1 + e.end) ] ]

                        else
                            []

                mouseEvents =
                    case model.state of
                        Idle ->
                            [ onMouseDown <| BeginCreateEvent index ]

                        Creating _ ->
                            [ onMouseEnter <| MouseEnterTime index
                            , onMouseUp <| EndCreateEvent
                            ]

                        Dragging _ ->
                            [ onMouseEnter <| DragEventTo index
                            , onMouseUp <| EndDragEvent
                            ]

                        Resizing _ ->
                            [ onMouseEnter <| ResizeEventTo index
                            , onMouseUp <| EndResizeEvent
                            ]
            in
            \_ ->
                td
                    ([ class "interval"
                     , classList
                        [ ( "first-row", i == 1 )
                        , ( "last-row", i == slots )
                        ]
                     ]
                        ++ mouseEvents
                    )
                <|
                    List.take 1 <|
                        List.reverse <|
                            (case matchingEvent of
                                Just e ->
                                    [ div
                                        [ class "event"
                                        , classList
                                            [ ( "event-start", e.start == index )
                                            , ( "event-end", e.end == index )
                                            , ( "dragging", e.dragging )
                                            ]
                                        , stopPropagationOn "mousedown" (Decode.succeed ( BeginDragEvent e index, True ))
                                        ]
                                      <|
                                        if e.start == index || i == 1 then
                                            (if e.start == index then
                                                [ button
                                                    [ class "event-resize"
                                                    , stopPropagationOn "mousedown" (Decode.succeed ( ResizeEvent Start e, True ))
                                                    ]
                                                    []
                                                ]

                                             else
                                                []
                                            )
                                                ++ [ p [ class "event-time" ]
                                                        [ text <| timeSlotToString e.start ++ " - "
                                                        , wbr [] []
                                                        , text <| timeSlotToString (1 + e.end)
                                                        ]
                                                   , button
                                                        [ onClick <| DeleteEvent e
                                                        , ignoreEvent "mouseup"
                                                        , ignoreEvent "mousedown"
                                                        , class "event-close"
                                                        , type_ "button"
                                                        ]
                                                        [ text "X" ]
                                                   ]

                                        else if e.end == index then
                                            [ button
                                                [ class "event-resize"
                                                , stopPropagationOn "mousedown" (Decode.succeed ( ResizeEvent End e, True ))
                                                ]
                                                []
                                            ]

                                        else
                                            []
                                    ]

                                Nothing ->
                                    []
                            )
                                ++ (matchingDraft
                                        |> Maybe.map (viewDraft >> List.singleton)
                                        |> Maybe.withDefault []
                                   )
    in
    table
        (class "week"
            :: (if model.state /= Idle then
                    [ onMouseLeave <| MouseLeaveCalendar ]

                else
                    []
               )
        )
        [ thead [ style "position" "sticky", style "top" "0" ]
            [ tr [ class "week-header" ]
                (days
                    |> Array.map viewDay
                    |> Array.toList
                )
            ]
        , tbody []
            (tr
                [ class "all-day-line" ]
                (days
                    |> Array.map viewAllDay
                    |> Array.toList
                )
                :: (List.range 1 slots
                        |> List.map
                            (\i ->
                                tr []
                                    (days
                                        |> Array.indexedMap (viewTime i)
                                        |> Array.toList
                                    )
                            )
                   )
            )
        ]
